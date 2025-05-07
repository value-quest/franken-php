# FrankenPHP Distribution

This package contains a standalone distribution of [FrankenPHP](https://frankenphp.dev/), a modern PHP application server built on top of the Caddy web server. It includes [PHP](https://www.php.net/), [Composer](https://getcomposer.org/), and all necessary libraries in a single, self-contained package.

## Installation

1. Extract the tarball:
   ```bash
   tar -xzf frankenphp-linux-amd64-php8*.tar.gz
   ```

2. All files are contained within the extracted directory - no system-wide installation is needed.

## Usage

### Basic Setup

1. **Set up the environment** (IMPORTANT - this must be sourced, not executed):
   ```bash
   source ./setup-env.sh
   ```

2. **Start the web server**:
   ```bash
   ./frankenphp run
   ```

3. **Visit** http://localhost:8000 in your browser

### Available Commands

After sourcing the setup script, you can use:
- `php` - PHP CLI
- `composer` - PHP Composer package manager
- `frankenphp` - FrankenPHP server

### Manual Server Start

To manually start the server with a custom configuration:

```bash
# Start the server using the default Caddyfile
./frankenphp run

# Use a custom Caddyfile
./frankenphp run --config path/to/custom/Caddyfile

# Run a PHP script directly
./frankenphp php-cli script.php
```

### Directory Structure

- `frankenphp` - The FrankenPHP binary
- `bin/` - PHP and Composer binaries
    - `php` - PHP CLI executable
    - `php-config` - PHP configuration utility
    - `phpize` - Extension building utility
    - `composer` - Composer package manager
- `lib/` - Shared libraries
    - `libphp.so` - PHP shared library
    - Various other shared libraries required by FrankenPHP and PHP
- `Caddyfile` - Default FrankenPHP server configuration
- `index.php` - Example PHP script showing version information
- `setup-env.sh` - Environment setup script

## Included PHP Extensions

This PHP build includes the following extensions:

- **Core Extensions**:
    - Core
    - date
    - filter
    - hash
    - json
    - pcre
    - PDO
    - Reflection
    - SPL
    - standard
    - zlib

- **Bundled Extensions**:
    - ctype
    - curl
    - dom
    - fileinfo
    - mbstring
    - mysqli
    - openssl
    - pdo_mysql
    - pdo_sqlite
    - session
    - tokenizer
    - xml

## Adding Custom PHP Extensions

To add a custom PHP extension:

1. Source the environment setup:
   ```bash
   source ./setup-env.sh
   ```

2. Use phpize to prepare the extension:
   ```bash
   cd /path/to/extension
   phpize
   ./configure
   make
   make install
   ```

3. Create a php.ini file in the root directory of your project to load the extension.

## Custom Configuration

### PHP Configuration

Create a `php.ini` file in the same directory as the FrankenPHP binary to customize PHP settings.

### FrankenPHP/Caddy Configuration

Edit the `Caddyfile` to change server settings, ports, or add virtual hosts.

## Troubleshooting

- **"Command not found" errors**: Make sure you've sourced the setup script with `source ./setup-env.sh` rather than executing it directly.
- **Port conflicts**: If port 8000 is already in use, edit the Caddyfile to use a different port.
- **Permission errors**: Ensure the binaries have executable permissions with `chmod +x frankenphp`.

## License

- FrankenPHP is licensed under the MIT License
- PHP is licensed under the PHP License
- Composer is licensed under the MIT License
