#!/bin/bash
# update.sh - Dedicated update script for FrankenPHP

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
MARKER="# FrankenPHP environment setup"

# Function to check if FrankenPHP processes are running
check_running_processes() {
    local running_processes=$(pgrep -f frankenphp 2>/dev/null || true)
    if [ -n "$running_processes" ]; then
        echo "⚠️  FrankenPHP processes are currently running:"
        ps aux | grep -v grep | grep frankenphp || true
        echo ""
        return 0
    fi
    return 1
}

# Function to stop services gracefully
stop_services() {
    echo "🛑 Stopping FrankenPHP services..."

    # Try supervisor first
    if command -v supervisorctl >/dev/null 2>&1; then
        echo "  - Stopping Supervisor services..."
        sudo supervisorctl stop all 2>/dev/null || true
        sleep 3
    fi

    # Kill any remaining FrankenPHP processes
    local remaining=$(pgrep -f frankenphp 2>/dev/null || true)
    if [ -n "$remaining" ]; then
        echo "  - Killing remaining FrankenPHP processes..."
        sudo pkill -f frankenphp 2>/dev/null || true
        sleep 2
    fi

    echo "✅ Services stopped"
}

# Function to restart services
restart_services() {
    echo "🔄 Restarting services..."

    if command -v supervisorctl >/dev/null 2>&1; then
        echo "  - Reloading Supervisor configuration..."
        sudo supervisorctl reread 2>/dev/null || true
        sudo supervisorctl update 2>/dev/null || true
        echo "  - Starting all services..."
        sudo supervisorctl start all 2>/dev/null || true

        # Show status
        echo ""
        echo "📊 Service status:"
        sudo supervisorctl status 2>/dev/null || echo "  Could not get status"
    else
        echo "  ⚠️  Supervisor not found - manual service restart required"
    fi
}

# Function to backup current installation
backup_installation() {
    local backup_dir="/tmp/frankenphp-backup-$(date +%Y%m%d-%H%M%S)"
    echo "📦 Creating backup at: $backup_dir"

    if [ "$EUID" -eq 0 ]; then
        mkdir -p "$backup_dir"/{bin,lib,libexec}
        for binary in frankenphp php composer node npm npx git sqlite3 zip unzip php-config phpize; do
            [ -f "/usr/local/bin/$binary" ] && cp "/usr/local/bin/$binary" "$backup_dir/bin/" 2>/dev/null || true
            [ -f "/usr/local/bin/$binary.real" ] && cp "/usr/local/bin/$binary.real" "$backup_dir/bin/" 2>/dev/null || true
        done
        [ -f "/usr/local/lib/libphp.so" ] && cp /usr/local/lib/libphp.so* "$backup_dir/lib/" 2>/dev/null || true
        [ -d "/usr/local/lib/node_modules" ] && cp -r /usr/local/lib/node_modules "$backup_dir/lib/" 2>/dev/null || true
        [ -d "/usr/local/libexec/git-core" ] && cp -r /usr/local/libexec/git-core "$backup_dir/libexec/" 2>/dev/null || true
    else
        [ -f "$HOME/.bash_profile" ] && cp "$HOME/.bash_profile" "${HOME}/.bash_profile.backup-$(date +%Y%m%d-%H%M%S)"
    fi

    echo "$backup_dir" > /tmp/frankenphp-last-backup
    echo "✅ Backup created"
}

# Function to show version comparison
show_version_comparison() {
    echo "=== VERSION COMPARISON ==="
    echo ""
    echo "CURRENT VERSIONS:"
    if [ "$EUID" -eq 0 ]; then
        /usr/local/bin/frankenphp version 2>/dev/null | head -1 | sed 's/^/  /' || echo "  FrankenPHP: not found"
        /usr/local/bin/php --version 2>/dev/null | head -1 | sed 's/^/  /' || echo "  PHP: not found"
        /usr/local/bin/node --version 2>/dev/null | sed 's/^/  Node.js: /' || echo "  Node.js: not found"
        /usr/local/bin/composer --version 2>/dev/null | head -1 | sed 's/^/  /' || echo "  Composer: not found"
    else
        command -v frankenphp >/dev/null && frankenphp version 2>/dev/null | head -1 | sed 's/^/  /' || echo "  FrankenPHP: not found"
        command -v php >/dev/null && php --version 2>/dev/null | head -1 | sed 's/^/  /' || echo "  PHP: not found"
        command -v node >/dev/null && echo "  Node.js: $(node --version)" || echo "  Node.js: not found"
        command -v composer >/dev/null && composer --version 2>/dev/null | head -1 | sed 's/^/  /' || echo "  Composer: not found"
    fi

    echo ""
    echo "NEW VERSIONS (from package):"
    echo "  FrankenPHP: $(cd "$SCRIPT_DIR" && ./bin/frankenphp.real version 2>/dev/null | head -1 || echo 'included')"
    echo "  PHP: $(cd "$SCRIPT_DIR" && ./bin/php.real --version 2>/dev/null | head -1 || echo 'included')"
    echo "  Node.js: $(cd "$SCRIPT_DIR" && ./bin/node --version 2>/dev/null || echo 'included')"
    echo "  Composer: $(cd "$SCRIPT_DIR" && LD_LIBRARY_PATH="$SCRIPT_DIR/lib" ./bin/composer --version 2>/dev/null | head -1 || echo 'included')"
    echo ""
}

# Function to clean old installation thoroughly
clean_old_installation() {
    if [ "$EUID" -eq 0 ]; then
        echo "🧹 Cleaning old installation..."

        # Remove old binaries
        for binary in frankenphp php composer node npm npx git sqlite3 zip unzip php-config phpize; do
            rm -f "/usr/local/bin/$binary" "/usr/local/bin/$binary.real" 2>/dev/null || true
        done

        # Remove old libraries (but keep system ones)
        rm -f /usr/local/lib/libphp.so* 2>/dev/null || true

        # Remove Node.js modules and git helpers
        rm -rf /usr/local/lib/node_modules /usr/local/libexec/git-core 2>/dev/null || true

        echo "✅ Old installation cleaned"
    else
        # For user installation, clean PATH entries
        local profile="$HOME/.bash_profile"
        if [ -f "$profile" ] && grep -q "$MARKER" "$profile"; then
            sed -i.bak "/^$MARKER/,/^# End of FrankenPHP environment setup/d" "$profile"
            echo "✅ Old user configuration cleaned"
        fi
    fi
}

# Function to perform the installation
perform_installation() {
    if [ "$EUID" -eq 0 ]; then
        echo "🔧 Installing system-wide..."
        mkdir -p /usr/local/lib /usr/local/libexec

        # Copy libraries first
        echo "  - Installing libraries..."
        cp -r "$SCRIPT_DIR/lib"/* /usr/local/lib/
        [ -d "$SCRIPT_DIR/libexec" ] && cp -r "$SCRIPT_DIR/libexec"/* /usr/local/libexec/

        # Update ldconfig
        echo "/usr/local/lib" > /etc/ld.so.conf.d/frankenphp.conf
        ldconfig 2>&1 | grep -v "is not a symbolic link" || true

        # Install git with wrapper (if present)
        if [ -f "$SCRIPT_DIR/bin/git.real" ]; then
            echo "  - Installing git..."
            cp "$SCRIPT_DIR/bin/git.real" "/usr/local/bin/git.real"
            chmod +x "/usr/local/bin/git.real"
            cat > "/usr/local/bin/git" << 'EOL'
#!/bin/bash
export GIT_EXEC_PATH="/usr/local/libexec/git-core"
exec "/usr/local/bin/git.real" "$@"
EOL
            chmod +x "/usr/local/bin/git"
        fi

        # Install binaries that need LD_LIBRARY_PATH
        echo "  - Installing PHP and FrankenPHP..."
        for binary in frankenphp php; do
            if [ -f "$SCRIPT_DIR/bin/$binary.real" ]; then
                cp "$SCRIPT_DIR/bin/$binary.real" "/usr/local/bin/$binary.real"
                chmod +x "/usr/local/bin/$binary.real"
                cat > "/usr/local/bin/$binary" << EOL
#!/bin/bash
export LD_LIBRARY_PATH="/usr/local/lib:\$LD_LIBRARY_PATH"
exec "/usr/local/bin/$binary.real" "\$@"
EOL
                chmod +x "/usr/local/bin/$binary"
            fi
        done

        # Install Node.js first (needed for npm/npx)
        if [ -f "$SCRIPT_DIR/bin/node" ]; then
            echo "  - Installing Node.js..."
            cp "$SCRIPT_DIR/bin/node" "/usr/local/bin/node"
            chmod +x "/usr/local/bin/node"
        fi

        # Install other binaries
        echo "  - Installing additional tools..."
        for binary in composer npm npx sqlite3 zip unzip php-config phpize; do
            if [ -f "$SCRIPT_DIR/bin/$binary" ]; then
                if [ "$binary" = "npm" ] || [ "$binary" = "npx" ]; then
                    # Node.js wrapper scripts (only if node is available)
                    if [ -f "/usr/local/bin/node" ]; then
                        cat > "/usr/local/bin/$binary" << EOL
#!/bin/bash
export NODE_PATH="/usr/local/lib/node_modules"
exec "/usr/local/bin/node" "/usr/local/lib/node_modules/npm/bin/$binary-cli.js" "\$@"
EOL
                        chmod +x "/usr/local/bin/$binary"
                    fi
                else
                    # Direct copy for other tools
                    cp "$SCRIPT_DIR/bin/$binary" "/usr/local/bin/$binary"
                    chmod +x "/usr/local/bin/$binary"
                fi
            fi
        done
    else
        # User installation
        echo "🔧 Installing for user..."
        local profile="$HOME/.bash_profile"

        [ ! -f "$profile" ] && cat > "$profile" << 'EOL'
if [ -f ~/.profile ]; then . ~/.profile; fi
if [ -f ~/.bashrc ]; then . ~/.bashrc; fi
EOL

        cat >> "$profile" << EOL
$MARKER
export PATH="$SCRIPT_DIR/bin:\$PATH"
export LD_LIBRARY_PATH="$SCRIPT_DIR/lib:\$LD_LIBRARY_PATH"
# End of FrankenPHP environment setup
EOL
    fi
}

# Function to verify installation
verify_installation() {
    echo ""
    echo "🔍 Verifying installation..."
    local all_good=true

    if [ "$EUID" -eq 0 ]; then
        # System installation verification
        if ! /usr/local/bin/frankenphp version >/dev/null 2>&1; then
            echo "  ❌ FrankenPHP verification failed"
            all_good=false
        else
            echo "  ✅ FrankenPHP: $(/usr/local/bin/frankenphp version 2>/dev/null | head -1)"
        fi

        if ! /usr/local/bin/php --version >/dev/null 2>&1; then
            echo "  ❌ PHP verification failed"
            all_good=false
        else
            echo "  ✅ PHP: $(/usr/local/bin/php --version 2>/dev/null | head -1)"
        fi

        if [ -f "/usr/local/bin/node" ] && ! /usr/local/bin/node --version >/dev/null 2>&1; then
            echo "  ❌ Node.js verification failed"
            all_good=false
        elif [ -f "/usr/local/bin/node" ]; then
            echo "  ✅ Node.js: $(/usr/local/bin/node --version 2>/dev/null)"
        fi

        if ! /usr/local/bin/composer --version >/dev/null 2>&1; then
            echo "  ⚠️  Composer verification failed (non-critical)"
        else
            echo "  ✅ Composer: $(/usr/local/bin/composer --version 2>/dev/null | head -1)"
        fi
    fi

    if [ "$all_good" = true ]; then
        echo "  🎉 All components verified successfully!"
    else
        echo "  ⚠️  Some components failed verification"
        return 1
    fi
}

# Main execution
main() {
    echo "🚀 FrankenPHP Update Script"
    echo "=========================="

    # Check if we're in the right directory
    if [ ! -f "$SCRIPT_DIR/bin/frankenphp.real" ]; then
        echo "❌ Error: Cannot find frankenphp.real in $SCRIPT_DIR/bin/"
        echo "   Make sure you're running this from the extracted FrankenPHP directory"
        exit 1
    fi

    # Check if installation exists
    if [ "$EUID" -eq 0 ]; then
        if [ ! -f "/usr/local/bin/frankenphp" ]; then
            echo "❌ No system-wide installation found. Use ./install.sh for new installations."
            exit 1
        fi
    else
        if ! grep -q "$MARKER" "$HOME/.bash_profile" 2>/dev/null; then
            echo "❌ No user installation found. Use ./install.sh for new installations."
            exit 1
        fi
    fi

    show_version_comparison

    echo "⚠️  This update will:"
    echo "   - Stop all FrankenPHP processes and services"
    echo "   - Replace all binaries (including Node.js)"
    echo "   - Restart Supervisor services automatically"
    echo "   - Create a backup of current installation"
    echo ""

    read -p "Continue with update? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && echo "❌ Update cancelled" && exit 1

    # Check and stop running processes
    if check_running_processes; then
        stop_services
    fi

    # Create backup
    backup_installation

    # Clean old installation
    clean_old_installation

    # Perform installation
    perform_installation

    # Verify installation
    if ! verify_installation; then
        echo ""
        echo "❌ Update completed but verification failed!"
        echo "📦 Restore from backup if needed: $(cat /tmp/frankenphp-last-backup 2>/dev/null || echo 'No backup info')"
        exit 1
    fi

    # Restart services
    restart_services

    echo ""
    echo "🎉 UPDATE COMPLETED SUCCESSFULLY!"
    echo ""
    echo "📦 Backup location: $(cat /tmp/frankenphp-last-backup 2>/dev/null || echo 'No backup info')"
    echo ""

    if [ "$EUID" -ne 0 ]; then
        echo "🔄 For user installation, reload your profile:"
        echo "   source ~/.bash_profile"
    fi
}

# Run main function
main "$@"
