# FrankenPHP Distribution

The releases contain a standalone distribution of [FrankenPHP](https://frankenphp.dev/), [PHP](https://www.php.net/), [Composer](https://getcomposer.org/), [Node.js](https://nodejs.org/), and all necessary libraries and development tools.
No further installation is needed to run your PHP app!

## Installation

1. Extract the tarball:
   ```bash
   tar -xzf frankenphp-linux-amd64-php8*.tar.gz
   ```

2. Install (choose one):
   
   **System-wide installation (recommended for servers):**
   ```bash
   sudo ./setup-env.sh
   ```
   
   **User installation (for development):**
   ```bash
   ./setup-env.sh
   source ~/.bash_profile
   ```

## Quick Start

After installation, test immediately:
```bash
frankenphp run
# Visit http://localhost:8080
```

## Available Commands

After installation, these commands are available globally:
- `frankenphp` - FrankenPHP web server
- `php` - PHP 8.x CLI
- `composer` - PHP package manager
- `node` - Node.js runtime
- `npm` / `npx` - Node.js package managers
- `git` - Version control
- `sqlite3` - SQLite database CLI
- `zip` / `unzip` - Archive utilities

## Usage Examples

### Basic Web Server
```bash
# Start server with included Caddyfile
frankenphp run

# Use custom Caddyfile
frankenphp run --config path/to/custom/Caddyfile

# Run on different port
frankenphp run --config Caddyfile --adapter caddyfile --listen :8090
```

### PHP Development
```bash
# Run PHP scripts
php script.php

# Check PHP version and extensions
php -v
php -m

# Install packages with Composer
composer install
composer require laravel/framework
```

### Node.js Development
```bash
# Run Node.js demo
node demo.js

# Install npm packages
npm install express
npx create-react-app my-app
```

## Directory Structure
```
.
├── bin/              # All executables
│   ├── frankenphp    # Self-contained wrapper
│   ├── php           # Self-contained wrapper
│   ├── composer
│   ├── node
│   ├── npm
│   └── ...
├── lib/              # Shared libraries
├── libexec/          # Git helper programs
├── Caddyfile         # Example server configuration
├── index.php         # PHP info demo
├── setup-env.sh      # Installation script
└── README.md
```

## PHP Extensions

This build includes all extensions needed for modern PHP applications:

### Core Extensions
- **Essentials**: ctype, date, dom, filter, hash, json, libxml, mbstring, pcre, PDO, session, SPL, standard, tokenizer, xml
- **Process Control**: pcntl (required for Laravel Octane)
- **Internationalization**: intl

### Database Support
- **MySQL/MariaDB**: mysqli, mysqlnd, pdo_mysql
- **SQLite**: sqlite3, pdo_sqlite

### Web & Network
- **HTTP**: curl, openssl
- **Compression**: zlib, zip
- **Graphics**: gd (with JPEG, PNG, FreeType support)

### Additional Features
- **Math**: bcmath
- **File Info**: fileinfo
- **XML**: SimpleXML, xmlreader, xmlwriter, xsl

## Laravel Octane Support

This distribution includes full support for Laravel Octane with:
- ext-pcntl for process management
- ZTS (Zend Thread Safety) enabled
- Compatible with Supervisor and systemd

## System-wide Installation Benefits

With system-wide installation (`sudo ./setup-env.sh`):
- Works with process managers (Supervisor, systemd)
- Available for all users
- No environment setup needed
- Binaries available at `/usr/local/bin/`

Example Supervisor configuration:
```ini
[program:laravel-worker]
command=/usr/local/bin/php /path/to/artisan queue:work
directory=/path/to/project
autostart=true
autorestart=true
```

## Custom Configuration

### PHP Configuration
Create a `php.ini` file in your project directory to customize PHP settings.

### Server Configuration
Edit the included `Caddyfile` or create your own:
```caddyfile
example.com {
    root * /path/to/public
    php_server
    encode gzip
}
```

## Troubleshooting

### Command Not Found
- For user installation: Run `source ~/.bash_profile`
- For system installation: Commands should work immediately

### Port Conflicts
- Default port is 8080
- Change in Caddyfile: `localhost:9090`

### Library Errors
- The distribution includes self-contained wrappers that handle library paths automatically
- For system-wide issues, reinstall with: `sudo ./setup-env.sh`

## Development Tools

### Git Workflow
```bash
git init
git add .
git commit -m "Initial commit"
git push origin main
```

### Database Operations
```bash
sqlite3 database.db
.tables
.schema users
```

### Archive Management
```bash
zip -r project.zip project/
unzip project.zip
```

## Uninstallation

### System-wide
```bash
sudo rm -f /usr/local/bin/{frankenphp,php,composer,node,npm,npx,git,sqlite3,zip,unzip}
sudo rm -f /etc/ld.so.conf.d/frankenphp.conf
sudo ldconfig
```

### User Installation
Remove from `~/.bash_profile`:
```
# FrankenPHP environment setup
...
# End of FrankenPHP environment setup
```

## License
- FrankenPHP: MIT License
- PHP: PHP License
- Composer: MIT License
- Node.js: MIT License
