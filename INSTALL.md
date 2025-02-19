# Requirements

* a PostgreSQL database with the **postgis** and **uuid-ossp** extensions installed
* Lizmap Web Client 3.7 or above

# Installation

### Automatic installation of files with Composer


* into `lizmap/my-packages`, create the file `composer.json` (if it doesn't exist)
  by copying the file `composer.json.dist`, and install the modules with Composer:

```bash
cp -n lizmap/my-packages/composer.json.dist lizmap/my-packages/composer.json
composer require --working-dir=lizmap/my-packages "lizmap/lizmap-import-module"
```


### Launching the installer with Lizmap Web Client 3.7


If you are using Lizmap Web Client **3.7 or higher**, execute

```bash
php lizmap/install/configurator.php import
```

It will ask you all parameters for the PostgreSQL database access, and also:

* The name of the **PostgreSQL role** that need to be granted with write access on the tables
  in the PostgreSQL schema `lizmap_import_module` (that will be created by the module installation
  script).

* Then, execute Lizmap install scripts into `lizmap/install/` :

```bash
php lizmap/install/installer.php
./lizmap/install/clean_vartmp.sh
./lizmap/install/set_rights.sh
```

Then a new schema `lizmap_import_module` must be visible in your PostgreSQL database, containing the needed
tables and functions used by the module.
