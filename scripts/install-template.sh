#!/bin/bash
# install.sh - Installation script for FrankenPHP (new installations only)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROFILE="$HOME/.bash_profile"
MARKER="# FrankenPHP environment setup"

# Function to detect existing installation
detect_existing_installation() {
    if [ "$EUID" -eq 0 ]; then
        if [ -f "/usr/local/bin/frankenphp" ]; then
            echo "❌ Existing system-wide installation detected!"
            echo "   Use ./update.sh for updates instead of install.sh"
            exit 1
        fi
    else
        if grep -q "$MARKER" "$PROFILE" 2>/dev/null; then
            echo "❌ Existing user installation detected!"
            echo "   Use ./update.sh for updates instead of install.sh"
            exit 1
        fi
    fi
}

# Function to show versions that will be installed
show_installation_info() {
    echo "=== NEW INSTALLATION ==="
    echo ""
    echo "Installing versions:"
    echo "  FrankenPHP: $(cd "$SCRIPT_DIR" && ./bin/frankenphp.real version 2>/dev/null | head -1 || echo 'included')"
    echo "  PHP: $(cd "$SCRIPT_DIR" && ./bin/php.real --version 2>/dev/null | head -1 || echo 'included')"
    echo "  Node.js: $(cd "$SCRIPT_DIR" && ./bin/node --version 2>/dev/null || echo 'included')"
    echo "  Composer: $(cd "$SCRIPT_DIR" && LD_LIBRARY_PATH="$SCRIPT_DIR/lib" ./bin/composer --version 2>/dev/null | head -1 || echo 'included')"
    echo ""
}

# System-wide installation function
install_system_wide() {
    echo "🔧 Installing system-wide..."
    mkdir -p /usr/local/lib /usr/local/libexec

    echo "  - Installing libraries..."
    cp -r "$SCRIPT_DIR/lib"/* /usr/local/lib/
    [ -d "$SCRIPT_DIR/libexec" ] && cp -r "$SCRIPT_DIR/libexec"/* /usr/local/libexec/

    echo "/usr/local/lib" > /etc/ld.so.conf.d/frankenphp.conf
    ldconfig 2>&1 | grep -v "is not a symbolic link" || true

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

    if [ -f "$SCRIPT_DIR/bin/node" ]; then
        echo "  - Installing Node.js..."
        cp "$SCRIPT_DIR/bin/node" "/usr/local/bin/node"
        chmod +x "/usr/local/bin/node"
    fi

    echo "  - Installing additional tools..."
    for binary in composer npm npx sqlite3 zip unzip php-config phpize; do
        if [ -f "$SCRIPT_DIR/bin/$binary" ]; then
            if [ "$binary" = "npm" ] || [ "$binary" = "npx" ]; then
                if [ -f "/usr/local/bin/node" ]; then
                    cat > "/usr/local/bin/$binary" << EOL
#!/bin/bash
export NODE_PATH="/usr/local/lib/node_modules"
exec "/usr/local/bin/node" "/usr/local/lib/node_modules/npm/bin/$binary-cli.js" "\$@"
EOL
                    chmod +x "/usr/local/bin/$binary"
                fi
            else
                cp "$SCRIPT_DIR/bin/$binary" "/usr/local/bin/$binary"
                chmod +x "/usr/local/bin/$binary"
            fi
        fi
    done

    echo ""
    echo "✅ System-wide installation completed!"
    echo ""
    echo "Installed versions:"
    /usr/local/bin/frankenphp version 2>/dev/null | head -1 | sed 's/^/  /' || echo "  FrankenPHP: ⚠️  error getting version"
    /usr/local/bin/php --version 2>/dev/null | head -1 | sed 's/^/  /' || echo "  PHP: ⚠️  error getting version"
    /usr/local/bin/composer --version 2>/dev/null | head -1 | sed 's/^/  /' || echo "  Composer: ⚠️  error getting version"
    /usr/local/bin/node --version 2>/dev/null | sed 's/^/  Node.js: /' || echo "  Node.js: ⚠️  error getting version"
    echo ""
    echo "📄 For future updates, use: ./update.sh"
}

# User installation function
install_user() {
    echo "🔧 Installing for user..."

    [ ! -f "$PROFILE" ] && cat > "$PROFILE" << 'EOL'
if [ -f ~/.profile ]; then . ~/.profile; fi
if [ -f ~/.bashrc ]; then . ~/.bashrc; fi
EOL

    cat >> "$PROFILE" << EOL
$MARKER
export PATH="$SCRIPT_DIR/bin:\$PATH"
export LD_LIBRARY_PATH="$SCRIPT_DIR/lib:\$LD_LIBRARY_PATH"
# End of FrankenPHP environment setup
EOL

    echo ""
    echo "✅ User installation completed!"
    echo ""
    echo "🔄 Activate the installation:"
    echo "   source ~/.bash_profile"
    echo ""
    echo "📄 For future updates, use: ./update.sh"
}

# Main execution
main() {
    echo "🚀 FrankenPHP Installation Script"
    echo "================================="

    if [ ! -f "$SCRIPT_DIR/bin/frankenphp.real" ]; then
        echo "❌ Error: Cannot find frankenphp.real in $SCRIPT_DIR/bin/"
        echo "   Make sure you're running this from the extracted FrankenPHP directory"
        exit 1
    fi

    detect_existing_installation
    show_installation_info

    if [ "$EUID" -eq 0 ]; then
        echo "👨‍💼 Running as root - will install system-wide"
        echo ""
        echo "This will:"
        echo "  - Install to /usr/local/bin and /usr/local/lib"
        echo "  - Make tools available to all users"
        echo "  - Work with Supervisor and systemd services"
        echo ""
        read -p "Continue? [y/N] " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && echo "❌ Installation cancelled" && exit 1

        install_system_wide
    else
        echo "👤 Running as user - will install for current user only"
        echo ""
        echo "This will:"
        echo "  - Modify ~/.bash_profile"
        echo "  - Only work for current user"
        echo "  - Require 'source ~/.bash_profile' after installation"
        echo ""
        read -p "Continue? [y/N] " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && echo "❌ Installation cancelled" && exit 1

        install_user
    fi
}

main "$@"
