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
   sudo ./install.sh
   ```

   **User installation (for development):**

   ```bash
   ./install.sh
   source ~/.bash_profile
   ```

## Multi-Version Installation (Build Servers)

For build servers that need multiple PHP versions installed side-by-side, use the `--versioned` option.

This installs the distribution into:

```bash
~/frankenphp/php<version>
~/frankenphp/php<version>
```

without modifying your default shell environment or replacing existing installations.

### Install a PHP version

```bash
mkdir -p ~/frankenphp/php8.4
cd ~/frankenphp/php8.4

tar -xzf ~/frankenphp-linux-amd64-php<version.tar.gz

./install.sh --versioned <version with dot (e.g. 8.4)>
```

### Using a Specific PHP Version

Temporarily prepend the desired version to your PATH:

```bash
export PATH="$HOME/frankenphp/php<version>/bin:$PATH"

php -v
composer --version
node -v
npm -v
```

This automatically switches:

* `php`
* `composer`
* `frankenphp`
* `node`
* `npm`
* `npx`
* `git`
* all included tools

The build/deploy scripts can select the appropriate version automatically based on `composer.json`.

## Updates

For existing installations, use the update script instead of install.sh:

```bash
# Get new version (head over to Releases)
wget https://github.com/value-quest/franken-php/releases/download/v[FrankenPHP version]/frankenphp-linux-amd64-php[8.4 / 8.5].tar.gz

# Extract new version
tar -xzf frankenphp-linux-amd64-php8*.tar.gz

# Update existing installation
sudo ./update.sh     # System-wide
./update.sh          # User installation
```

### Multi-Version Updates

For versioned build-server installations:

```bash
cd ~/frankenphp/php8.4
./update.sh --versioned 8.4

cd ~/frankenphp/php8.5
./update.sh --versioned 8.5
```

The update script replaces the installation atomically while preserving other installed PHP versions.

## Installation Scripts

* **install.sh**

    * New installations
    * Supports `--versioned`
    * Detects existing installations and redirects to update.sh

* **update.sh**

    * Updates existing installations
    * Supports `--versioned`
    * Includes automatic service management for standard installations:

        * Stops FrankenPHP processes gracefully
        * Creates backup before updating
        * Replaces all binaries and libraries
        * Restarts Supervisor services automatically

## Quick Start

After installation, test immediately:

```bash
frankenphp run
# Visit http://localhost:8000
```

## Available Commands

After installation, these commands are available globally:

* `frankenphp` - FrankenPHP web server
* `php` - PHP 8.x CLI
* `composer` - PHP package manager
* `node` - Node.js runtime
* `npm` / `npx` - Node.js package managers
* `git` - Version control
* `sqlite3` - SQLite database CLI
* `zip` / `unzip` - Archive utilities

## Usage Examples

### Basic Web Server

```bash
# Start server
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

```text
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
├── install.sh        # New installation script
├── update.sh         # Update existing installation script
└── README.md
```

## PHP Extensions

This build includes all extensions needed for modern PHP applications.

### Core Extensions

* **Essentials**: ctype, date, dom, filter, hash, json, libxml, mbstring, pcre, session, SPL, standard, tokenizer, xml
* **Process Control**: pcntl (required for Laravel Octane)
* **Internationalization**: intl

### Database Support

* **MySQL/MariaDB**: mysqli, mysqlnd, pdo_mysql
* **SQLite**: sqlite3, pdo_sqlite

### Web & Network

* **HTTP**: curl, openssl
* **Compression**: zlib, zip
* **Graphics**: gd (with JPEG, PNG, FreeType support)
* **Sockets**: sockets

### Additional Features

* **Math**: bcmath
* **File Info**: fileinfo, exif
* **Web Services**: soap
* **Performance**: opcache

## Laravel Octane Support

This distribution includes full support for Laravel Octane with:

* ext-pcntl for process management
* ZTS (Zend Thread Safety) enabled
* Compatible with Supervisor and systemd

## System-wide Installation Benefits

With system-wide installation (`sudo ./install.sh`):

* Works with process managers (Supervisor, systemd)
* Available for all users
* No environment setup needed
* Binaries available at `/usr/local/bin/`

Example Supervisor configuration:

```ini
[program:laravel-worker]
command=/usr/local/bin/php /path/to/artisan queue:work
directory=/path/to/project
autostart=true
autorestart=true
```

## Production Server Updates

For production servers using Supervisor, the recommended update process:

1. Extract new version
2. Run update script
3. Verify versions
4. Restart Supervisor if needed

The update script automatically:

* Creates backups
* Stops running FrankenPHP processes
* Replaces all binaries including Node.js
* Handles library dependencies

## Custom Configuration

### PHP Configuration

Create a `php.ini` file in your project directory to customize PHP settings.

### Server Configuration

Create a `Caddyfile` with the following content:

```caddyfile
example.com {
    root * /path/to/public
    php_server
    encode gzip
}
```

## Troubleshooting

### Command Not Found

* For user installation: Run `source ~/.bash_profile`
* For system installation: Commands should work immediately

### Versioned Installation Not Found

Verify the selected PATH:

```bash
echo $PATH
which php
which composer
```

Expected:

```bash
/home/administrator/frankenphp/php8.4/bin/php
```

### Port Conflicts

* Default port is 8000
* Change in Caddyfile: `localhost:9090`

### Update Issues

* Verify versions after updating:

  ```bash
  php -v
  composer --version
  node -v
  ```

### Library Errors

The distribution includes self-contained wrappers that automatically configure library paths.

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
sudo rm -f /usr/local/bin/*.real
sudo rm -rf /usr/local/lib/node_modules /usr/local/libexec/git-core
sudo rm -f /usr/local/lib/libphp.so* \
    /usr/local/lib/libicu*.so.* \
    /usr/local/lib/libgd.so.* \
    /usr/local/lib/libpng*.so.* \
    /usr/local/lib/libcurl.so.* \
    /usr/local/lib/libzip.so.* \
    /usr/local/lib/libonig.so.* \
    /usr/local/lib/libxml2.so.* \
    /usr/local/lib/libjpeg.so.* \
    /usr/local/lib/libxslt.so.* \
    /usr/local/lib/libfreetype.so.*
sudo ldconfig
```

### User Installation

```bash
rm -rf ~/bin/{composer,frankenphp,frankenphp.real,git,git.real,node,npm,npx,php,php.real,php-config,phpize,sqlite3,unzip,zip} ~/lib ~/libexec
```

### Versioned Installation

```bash
rm -rf ~/frankenphp/php8.4
rm -rf ~/frankenphp/php8.5
```

## License

* FrankenPHP: MIT License
* PHP: PHP License
* Composer: MIT License
* Node.js: MIT License
