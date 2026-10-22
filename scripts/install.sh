#!/bin/bash
# Installs or updates the FrankenPHP distribution. The same file ships as
# install.sh and update.sh; the name it is invoked by selects the mode.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
exec 1>&2

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
    echo "  Composer: $(cd "$SCRIPT_DIR" && LD_LIBRARY_PATH="$SCRIPT_DIR/lib" ./bin/composer --version 2>/dev/null | head -1 || echo 'included')"
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
    old=$(grep -oE "$HOME/(bin|lib)\.old/[^ ]+|[^ ]*(frankenphp|libphp)[^ ]* \(deleted\)" <<< "$maps" | head -1)
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

# Lists other processes still executing the replaced binaries, e.g. queue
# workers, which are left alone so they can finish their current job.
report_stale_processes() {
    local pid found=""

    for pid in $(pgrep -u "$EUID" -f '\.real( |$)' || true); do
        [[ "$(runs_from "$pid")" == "$HOME/"*.old/* ]] || continue
        found+=$'\n'"  PID $pid: $(tr '\0' ' ' < "/proc/$pid/cmdline" | cut -c1-120)"
    done

    if [ -n "$found" ]; then
        echo ""
        echo "Warning: these processes still run the previous version:$found"
        echo "Restart them (queue workers: php artisan queue:restart)."
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

    stop_services
    [ "$MODE" = install ] && remove_everything
    install_tree
    [ "$MODE" = update ] && SWAPPED=true
    update_profile
    verify_installed "$HOME"
    link_octane_binary
    start_services
    verify_running
    report_stale_processes
    rm -rf "$HOME/bin.old" "$HOME/lib.old" "$HOME/libexec.old"

    echo ""
    echo "${MODE^^} COMPLETED"
    echo "Run: source ~/.bash_profile"
    echo "Then test: php -v && node -v && frankenphp version"
}

main "$@"
