#!/bin/bash
# Installs or updates the FrankenPHP distribution. The same file ships as
# install.sh and update.sh; the name it is invoked by selects the mode.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# The installation, the server processes and their user services belong to
# the user, so under sudo run as that user (it still uses sudo for system
# services) rather than updating /root.
if [ "$EUID" -eq 0 ] && [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    exec sudo -u "$SUDO_USER" -H -- "$SCRIPT_DIR/$(basename "$0")" "$@"
fi

exec 1>&2

# Extracting the package into $HOME (wget, tar, ./update.sh in ~) has already
# replaced bin, lib and libexec, so there is nothing to swap or roll back to.
IN_PLACE=false
[ "$SCRIPT_DIR" -ef "$HOME" ] && IN_PLACE=true

case "$(basename "$0")" in
    update.sh) MODE=update ;;
    *)         MODE=install ;;
esac

VERSIONED_INSTALL=false
PHP_VERSION=""

if [ "${1:-}" = "--versioned" ]; then
    VERSIONED_INSTALL=true
    PHP_VERSION="${2:-}"

    if [[ ! "$PHP_VERSION" =~ ^8\.[0-9]+$ ]]; then
        echo "Usage: ./$MODE.sh --versioned 8.4|8.5"
        exit 1
    fi
fi

# Seconds to wait for the restarted web server to come up on the new binaries
VERIFY_TIMEOUT="${VERIFY_TIMEOUT:-60}"

# Matches FrankenPHP servers (direct or spawned by Octane) and Octane masters
SERVER_PATTERN='frankenphp(\.real)? (run|php-server)|artisan octane:(start|frankenphp)'

NEW_PHP_VERSION=""
SWAPPED=false
SERVICES=()
UNMANAGED_PIDS=()
OCTANE_APPS=()
[ -n "${OCTANE_APP_DIR:-}" ] && OCTANE_APPS+=("$OCTANE_APP_DIR")

as_root() {
    if [ "$EUID" -eq 0 ]; then "$@"; else sudo -n "$@"; fi
}

# Writes to stderr explicitly: it is also called inside command substitutions.
fail() {
    {
        echo ""
        echo "Error: $*"
        [ "$SWAPPED" = true ] && rollback_hint
    } >&2
    exit 1
}

show_versions() {
    echo "=== NEW VERSIONS ==="
    echo "  FrankenPHP: $(cd "$SCRIPT_DIR" && LD_LIBRARY_PATH="$SCRIPT_DIR/lib" ./bin/frankenphp.real version 2>/dev/null | head -1 || echo 'included')"
    echo "  PHP: $(cd "$SCRIPT_DIR" && LD_LIBRARY_PATH="$SCRIPT_DIR/lib" ./bin/php.real --version 2>/dev/null | head -1 || echo 'included')"
    echo "  Node.js: $(cd "$SCRIPT_DIR" && ./bin/node --version 2>/dev/null || echo 'included')"
    echo "  Composer: $(cd "$SCRIPT_DIR" && LD_LIBRARY_PATH="$SCRIPT_DIR/lib" ./bin/php.real ./bin/composer --version 2>/dev/null | head -1 || echo 'included')"
    echo ""
}

# Runs the packaged binaries in place before anything is stopped, so a broken
# or wrong-architecture package aborts without downtime.
preflight() {
    local out

    out=$(LD_LIBRARY_PATH="$SCRIPT_DIR/lib" "$SCRIPT_DIR/bin/php.real" -r 'echo PHP_VERSION;' 2>&1) ||
        fail "the packaged PHP does not run on this machine ($(uname -m)), nothing was changed:"$'\n'"$out"
    NEW_PHP_VERSION="$out"

    # php-cli runs FrankenPHP's own libphp, which is what serves requests
    out=$(LD_LIBRARY_PATH="$SCRIPT_DIR/lib" "$SCRIPT_DIR/bin/frankenphp.real" php-cli -r 'echo PHP_VERSION;' 2>&1) ||
        fail "the packaged FrankenPHP does not run on this machine ($(uname -m)), nothing was changed:"$'\n'"$out"
    [ "$out" = "$NEW_PHP_VERSION" ] ||
        fail "the packaged FrankenPHP runs PHP $out, expected $NEW_PHP_VERSION, nothing was changed"
}

# Checks that the binaries installed in $1/bin report the packaged PHP version.
verify_installed() {
    local bin="$1/bin" out

    out=$("$bin/php" -r 'echo PHP_VERSION;' 2>&1) || fail "installed php does not run:"$'\n'"$out"
    [ "$out" = "$NEW_PHP_VERSION" ] || fail "installed php reports $out, expected $NEW_PHP_VERSION"

    out=$("$bin/frankenphp" php-cli -r 'echo PHP_VERSION;' 2>&1) || fail "installed frankenphp does not run:"$'\n'"$out"
    [ "$out" = "$NEW_PHP_VERSION" ] || fail "installed frankenphp runs PHP $out, expected $NEW_PHP_VERSION"

    echo "Installed binaries run PHP $NEW_PHP_VERSION"
}

server_pids() {
    pgrep -u "$EUID" -f "$SERVER_PATTERN" || true
}

# Prints the ancestor of PID (or PID itself) that supervisord started, if any.
# Octane's FrankenPHP is a child of the supervised process.
supervised_ancestor() {
    local pid=$1 ppid

    while [ -n "$pid" ] && [ "$pid" -gt 1 ]; do
        ppid=$(ps -o ppid= -p "$pid" | tr -d ' ')
        [ -n "$ppid" ] || return 0
        if [ "$(ps -o comm= -p "$ppid")" = supervisord ]; then
            echo "$pid"
            return 0
        fi
        pid=$ppid
    done
}

# Prints the service managing PID as supervisor:<program>, systemd:<unit> or
# systemd-user:<unit>; prints nothing when no service manager owns it.
# Supervisor is found through the process tree because containers often have
# no systemd cgroups.
service_of_pid() {
    local pid=$1 child program cgroup unit

    child=$(supervised_ancestor "$pid")
    if [ -n "$child" ]; then
        program=$(as_root supervisorctl status 2>/dev/null |
            awk -v needle="pid $child," 'index($0, needle) { print $1 }')
        [ -n "$program" ] ||
            fail "PID $pid runs under Supervisor, but its program could not be identified (is 'sudo supervisorctl status' allowed?), nothing was changed"
        echo "supervisor:$program"
        return 0
    fi

    cgroup=$(cat "/proc/$pid/cgroup" 2>/dev/null) || return 0
    unit=$(grep -oE '[^/]+\.service' <<< "$cgroup" | grep -v '^user@' | tail -1)
    [ -n "$unit" ] || return 0

    # Only a unit that starts the server itself, not e.g. cron.service
    if [[ "$cgroup" == *"/user@"* ]]; then
        systemctl --user show -p ExecStart --value "$unit" 2>/dev/null | grep -qE 'frankenphp|octane|php' &&
            echo "systemd-user:$unit"
    else
        systemctl show -p ExecStart --value "$unit" 2>/dev/null | grep -qE 'frankenphp|octane|php' &&
            echo "systemd:$unit"
    fi
    return 0
}

service_ctl() {
    local action=$1 service=$2

    case "$service" in
        supervisor:*)   as_root supervisorctl "$action" "${service#supervisor:}" ;;
        systemd:*)      as_root systemctl "$action" "${service#systemd:}" ;;
        systemd-user:*) systemctl --user "$action" "${service#systemd-user:}" ;;
    esac
}

# Finds the units running the web server and stops them through their service
# manager. Killing the processes instead lets Supervisor respawn them while the
# installation is half replaced.
stop_services() {
    local pid service cmdline app

    for pid in $(server_pids); do
        service=$(service_of_pid "$pid")
        if [ -n "$service" ]; then
            [[ " ${SERVICES[*]} " == *" $service "* ]] || SERVICES+=("$service")
        else
            UNMANAGED_PIDS+=("$pid")
        fi

        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || continue
        if [[ "$cmdline" == *"artisan octane:"* ]]; then
            app=$(readlink "/proc/$pid/cwd" 2>/dev/null) || continue
            [[ " ${OCTANE_APPS[*]} " == *" $app "* ]] || OCTANE_APPS+=("$app")
        fi
    done

    if [ ${#SERVICES[@]} -eq 0 ] && [ ${#UNMANAGED_PIDS[@]} -eq 0 ]; then
        echo "No running FrankenPHP server found."
        return 0
    fi

    for service in "${SERVICES[@]}"; do
        echo "Stopping $service..."
        service_ctl stop "$service" || fail "could not stop $service, nothing was changed"
    done

    if [ ${#UNMANAGED_PIDS[@]} -gt 0 ]; then
        echo "Stopping FrankenPHP processes not managed by a service (they will NOT be restarted): ${UNMANAGED_PIDS[*]}"
        kill "${UNMANAGED_PIDS[@]}" 2>/dev/null || true
        for _ in $(seq 1 10); do
            kill -0 "${UNMANAGED_PIDS[@]}" 2>/dev/null || break
            sleep 1
        done
    fi
}

start_services() {
    local service

    for service in "${SERVICES[@]}"; do
        echo "Starting $service..."
        service_ctl start "$service" || fail "could not start $service"
    done
}

# Octane runs <app>/frankenphp when it exists. Pointing it at this installation
# keeps a binary Octane downloaded on its own from shadowing the update.
link_octane_binary() {
    local app

    for app in "${OCTANE_APPS[@]}"; do
        [ -f "$app/artisan" ] || continue
        [ "$(readlink "$app/frankenphp" 2>/dev/null)" = "$HOME/bin/frankenphp" ] && continue
        echo "Linking $app/frankenphp -> $HOME/bin/frankenphp"
        ln -sfn "$HOME/bin/frankenphp" "$app/frankenphp"
    done
}

# Prints "new" when PID has the new frankenphp and libphp mapped, "php" for
# the new PHP CLI (an Octane master), or the stale file it runs otherwise.
# Reads mapped files rather than /proc/PID/exe, which points at the
# emulator under Rosetta or QEMU.
runs_from() {
    local maps old

    maps=$(cat "/proc/$1/maps" 2>/dev/null) || return 0
    old=$(grep -oE "$HOME/(bin|lib)\.old/[^ ]+|[^ ]*(frankenphp|libphp|php\.real)[^ ]* \(deleted\)" <<< "$maps" | head -1)
    if [ -n "$old" ]; then
        echo "$old"
    elif [[ "$maps" == *" $HOME/bin/frankenphp.real"* && "$maps" == *" $HOME/lib/libphp.so"* ]]; then
        echo new
    elif [[ "$maps" == *" $HOME/bin/php.real"* ]]; then
        echo php
    else
        readlink "/proc/$1/exe" 2>/dev/null || echo unknown
    fi
}

# Waits until the restarted web server runs from the new installation: at
# least one FrankenPHP process on the new binary and libphp, and no server
# process left on anything else.
verify_running() {
    local deadline=$((SECONDS + VERIFY_TIMEOUT)) pid running ok stale

    [ ${#SERVICES[@]} -gt 0 ] || return 0

    while :; do
        ok=false
        stale=""
        for pid in $(server_pids); do
            running=$(runs_from "$pid")
            case "$running" in
                new) ok=true ;;
                php|"") ;;
                *) stale+=$'\n'"  PID $pid: $running" ;;
            esac
        done

        if [ "$ok" = true ] && [ -z "$stale" ]; then
            echo "Web server is running PHP $NEW_PHP_VERSION from $HOME/bin"
            return 0
        fi
        [ "$SECONDS" -ge "$deadline" ] && break
        sleep 2
    done

    if [ -n "$stale" ]; then
        fail "after ${VERIFY_TIMEOUT}s the web server still runs other binaries:$stale"
    fi
    fail "after ${VERIFY_TIMEOUT}s no FrankenPHP process runs from $HOME/bin (${SERVICES[*]})"
}

# Restarts queue workers still executing the replaced binaries with
# queue:restart, so they finish their current job before their service starts
# them again on the new PHP. Other such processes, e.g. litestream:replicate
# which only supervises the Litestream binary, keep working on the old PHP and
# are only listed.
restart_stale_processes() {
    local pid running cmdline artisan app left=""
    local queue_apps=()

    for pid in $(pgrep -u "$EUID" -f '\.real( |$)' || true); do
        running=$(runs_from "$pid")
        [[ "$running" == "$HOME/"*.old/* || "$running" == *" (deleted)" ]] || continue
        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || continue

        if [[ "$cmdline" == *"artisan queue:work"* ]]; then
            artisan=$(grep -oE '[^ ]*artisan queue:work' <<< "$cmdline" | head -1)
            artisan=${artisan% queue:work}
            [[ "$artisan" == /* ]] || artisan="$(readlink "/proc/$pid/cwd")/$artisan" || continue
            app=$(dirname "$artisan")
            [[ " ${queue_apps[*]} " == *" $app "* ]] || queue_apps+=("$app")
            continue
        fi

        left+=$'\n'"  PID $pid: ${cmdline:0:120}"
    done

    for app in "${queue_apps[@]}"; do
        echo "Restarting queue workers of $app after their current job..."
        (cd "$app" && "$HOME/bin/php" artisan queue:restart) ||
            left+=$'\n'"  queue workers of $app (php artisan queue:restart failed)"
    done

    if [ -n "$left" ]; then
        echo ""
        echo "Still on the previous version (restart them if they need the new PHP):$left"
    fi
}

# Prints the Supervisor programs whose command runs from this installation.
installation_programs() {
    local conf

    for conf in /etc/supervisor/supervisord.conf /etc/supervisor/conf.d/* /etc/supervisord.conf /etc/supervisord.d/*; do
        [ -f "$conf" ] || continue
        cat "$conf" 2>/dev/null || as_root cat "$conf" 2>/dev/null || true
    done | awk -v bin="$HOME/bin/" '
        /^\[program:/ { name = substr($0, 10); sub(/\].*/, "", name); next }
        /^\[/         { name = ""; next }
        name != "" && /^command *=/ && index($0, bin) { print name }'
}

# Whether $1, a process as supervisorctl names it (group:name, name_00 with
# numprocs), belongs to one of the programs in $2.
is_installation_program() {
    local process=${1#*:} program

    while read -r program; do
        [[ -n "$program" && ( "$process" == "$program" || "$process" == "$program"_* ) ]] && return 0
    done <<< "$2"
    return 1
}

# Starts the programs of this installation that Supervisor gave up on (FATAL),
# e.g. because an earlier update removed their binary, then shows all programs
# and warns about those of this installation that are not running.
check_supervisor() {
    local programs status name state not_running deadline=$((SECONDS + 15))

    command -v supervisorctl >/dev/null || return 0
    status=$(as_root supervisorctl status 2>/dev/null || true)
    [ -n "$status" ] || return 0
    programs=$(installation_programs)
    [ -n "$programs" ] || return 0

    while read -r name state _; do
        [ "$state" = FATAL ] && is_installation_program "$name" "$programs" || continue
        echo "Starting $name, which Supervisor had given up on..."
        as_root supervisorctl start "$name" < /dev/null || true
    done <<< "$status"

    # Restarted queue workers and programs pass through STARTING and BACKOFF
    while :; do
        status=$(as_root supervisorctl status 2>/dev/null || true)
        not_running=""
        while read -r name state _; do
            is_installation_program "$name" "$programs" || continue
            [ "$state" = RUNNING ] || not_running+=" $name ($state)"
        done <<< "$status"
        [[ -z "$not_running" || "$not_running" != *"(STARTING)"* && "$not_running" != *"(BACKOFF)"* ]] && break
        [ "$SECONDS" -ge "$deadline" ] && break
        sleep 1
    done

    echo ""
    echo "Supervisor programs:"
    sed 's/^/  /' <<< "$status"

    if [ -n "$not_running" ]; then
        echo ""
        echo "Warning: these programs of this installation are not running:$not_running"
        echo "Check: sudo supervisorctl tail <program> stderr"
    else
        echo "All Supervisor programs running from $HOME/bin are RUNNING."
    fi
}

rollback_hint() {
    echo "The previous installation is kept in $HOME/{bin,lib,libexec}.old. To roll back:"
    echo "  for d in bin lib libexec; do [ -d ~/\$d.old ] && rm -rf ~/\$d && mv ~/\$d.old ~/\$d; done"
    [ ${#SERVICES[@]} -gt 0 ] && echo "  then restart: ${SERVICES[*]}"
}

install_versioned() {
    local target="$HOME/frankenphp/php$PHP_VERSION"
    local tmp="$target.new"
    local backup="$target.backup.$(date +%Y%m%d-%H%M%S)"

    echo "Installing versioned FrankenPHP PHP $PHP_VERSION"
    echo "Target: $target"
    echo ""

    rm -rf "$tmp"
    mkdir -p "$tmp"

    cp -r "$SCRIPT_DIR/bin" "$tmp/"
    cp -r "$SCRIPT_DIR/lib" "$tmp/"
    [ -d "$SCRIPT_DIR/libexec" ] && cp -r "$SCRIPT_DIR/libexec" "$tmp/"

    chmod +x "$tmp/bin/"*

    if [ -d "$target" ]; then
        mv "$target" "$backup"
        echo "Previous version backed up to: $backup"
    fi

    mv "$tmp" "$target"
    verify_installed "$target"

    echo ""
    echo "Versioned install completed."
    echo "Test"
    echo "-------------------------------"
    echo "export PATH=\"$target/bin:\$PATH\""
    echo "which php"
    echo "php -v"
    echo ""
    echo "which composer"
    echo "composer --version"
    echo ""
    echo "which node"
    echo "  node -v"
}

remove_everything() {
    echo "Removing existing user installation..."
    rm -rf "$HOME/bin" "$HOME/lib" "$HOME/libexec"

    if [ "$EUID" -eq 0 ]; then
        rm -f /usr/local/bin/{frankenphp,php,composer,node,npm,npx,git,sqlite3,zip,unzip}
        rm -f /usr/local/bin/*.real
        rm -rf /usr/local/lib/node_modules /usr/local/libexec/git-core
        rm -f /usr/local/lib/libphp.so*
        rm -f /etc/ld.so.conf.d/frankenphp.conf
        ldconfig 2>/dev/null || true
    fi
}

# Swaps bin, lib and libexec for the packaged ones, keeping the previous trees
# as *.old until the update is verified. Files in ~/bin that are not part of
# the distribution (e.g. the deploy script) are carried over.
install_tree() {
    local dir

    if [ "$IN_PLACE" = true ]; then
        echo "Package was extracted into $HOME, files are already in place."
        return 0
    fi

    echo "Installing to $HOME..."

    for dir in bin lib libexec; do
        [ -d "$SCRIPT_DIR/$dir" ] || continue
        rm -rf "$HOME/$dir.new" "$HOME/$dir.old"
        if [ "$dir" = bin ] && [ -d "$HOME/bin" ]; then
            cp -a "$HOME/bin" "$HOME/bin.new"
        else
            mkdir -p "$HOME/$dir.new"
        fi
        cp -a "$SCRIPT_DIR/$dir/." "$HOME/$dir.new/"
    done
    chmod +x "$HOME/bin.new"/*

    for dir in bin lib libexec; do
        [ -d "$HOME/$dir.new" ] || continue
        [ -d "$HOME/$dir" ] && mv "$HOME/$dir" "$HOME/$dir.old"
        mv "$HOME/$dir.new" "$HOME/$dir"
    done
}

update_profile() {
    local profile="$HOME/.bash_profile"
    local marker="# FrankenPHP environment setup"

    if [ -f "$profile" ] && grep -q "$marker" "$profile"; then
        sed -i.bak "/^$marker/,/^# End of FrankenPHP environment setup/d" "$profile"
    fi

    [ ! -f "$profile" ] && cat > "$profile" << 'EOFPROFILE'
if [ -f ~/.profile ]; then . ~/.profile; fi
if [ -f ~/.bashrc ]; then . ~/.bashrc; fi
EOFPROFILE

    cat >> "$profile" << EOFPROFILE
$marker
export PATH="$HOME/bin:\$PATH"
# End of FrankenPHP environment setup
EOFPROFILE
}

main() {
    echo "franken-php $MODE"
    echo "==================="

    if [ ! -f "$SCRIPT_DIR/bin/frankenphp.real" ]; then
        echo "Error: Cannot find frankenphp.real in $SCRIPT_DIR/bin/"
        exit 1
    fi

    show_versions
    preflight

    if [ "$VERSIONED_INSTALL" = true ]; then
        install_versioned
        exit 0
    fi

    # Updating a user who has no installation, e.g. root in a root shell,
    # would install next to the real one and find none of its processes.
    if [ "$MODE" = update ] && [ ! -f "$HOME/bin/frankenphp.real" ]; then
        fail "no installation found in $HOME, nothing was changed."$'\n'"Run update.sh as the user that owns the installation (sudo ./update.sh switches to it)."
    fi

    stop_services
    [ "$MODE" = install ] && [ "$IN_PLACE" = false ] && remove_everything
    install_tree
    [ "$MODE" = update ] && [ "$IN_PLACE" = false ] && SWAPPED=true
    update_profile
    verify_installed "$HOME"
    link_octane_binary
    start_services
    verify_running
    restart_stale_processes
    check_supervisor
    rm -rf "$HOME/bin.old" "$HOME/lib.old" "$HOME/libexec.old"

    echo ""
    echo "${MODE^^} COMPLETED"
    echo "Run: source ~/.bash_profile"
    echo "Then test: php -v && node -v && frankenphp version"
}

main "$@"
