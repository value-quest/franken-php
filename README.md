# FrankenPHP Distribution

The releases contain a standalone distribution of [FrankenPHP](https://frankenphp.dev/), [PHP](https://www.php.net/), [Composer](https://getcomposer.org/), [Node.js](https://nodejs.org/), and all necessary libraries and development tools.
No further installation is needed to run your PHP app!

## Installation

Releases are built for `amd64` (`x86_64`) and `arm64` (`aarch64`). Pick the tarball matching `uname -m`.

1. Extract the tarball:

   ```bash
   tar -xzf frankenphp-linux-<amd64|arm64>-php8*.tar.gz
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
wget https://github.com/value-quest/franken-php/releases/download/v[FrankenPHP version]/frankenphp-linux-[amd64 / arm64]-php[84 / 85].tar.gz

# Extract new version
tar -xzf frankenphp-linux-*-php8*.tar.gz

# Update existing installation
./update.sh          # or: sudo ./update.sh (runs as your user, updates ~/bin)
```

Extracting the tarball into `~` and running `./update.sh` there works too; the files are then already in place and there is no previous version to roll back to.

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

        * Runs the new binaries before touching anything, so a broken or wrong-architecture package aborts without downtime
        * Finds the Supervisor program or systemd unit that runs the web server (FrankenPHP or Octane) and stops it through that service manager
        * Replaces binaries and libraries, keeping other files in `~/bin` (e.g. a deploy script)
        * Links Octane's `<app>/frankenphp` to `~/bin/frankenphp`
        * Starts the same unit again and waits until FrankenPHP runs the new binaries and `libphp.so` (`VERIFY_TIMEOUT`, default 60s)
        * Keeps the previous installation as `~/{bin,lib,libexec}.old` until verification succeeds, and prints rollback steps if it fails
        * Restarts queue workers still on the old version via `php artisan queue:restart` (after their current job) and lists other processes still on it
        * Starts Supervisor programs running from `~/bin` that Supervisor gave up on (`FATAL`), shows all programs and warns about any of them not running

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

The update script automatically:

* Verifies the new package runs on this machine before stopping anything
* Stops and restarts the web server's Supervisor program or systemd unit (sudo needs `supervisorctl status`, `stop`, `start` and `restart`)
* Replaces all binaries including Node.js
* Checks that the restarted server actually runs the new PHP version
* Restarts queue workers still running the previous PHP
* Starts Supervisor programs that are `FATAL` and shows the status of all programs

### Laravel Octane

Octane runs `<app>/frankenphp` when that file exists, which would shadow the updated binary.
Make it a symlink to the distribution and keep your deploy from overwriting it:

```bash
ln -sfn ~/bin/frankenphp ~/app/frankenphp
rsync ... --exclude=/frankenphp ...
```

`update.sh` creates or repairs the symlink for every running Octane app it finds (or `OCTANE_APP_DIR`).

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
