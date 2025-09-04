# Changelog

## Unreleased

## 1.4.0 - 2025-09-04

* Add a configuration option to choose which action is allowed
  between `insert`, `update` or `upsert`
* Add the capability to get geometries from a `wkt` column in the CSV
  instead of `longitude` and `latitude`
* Add compatibility with Lizmap Web Client 3.9

## 1.3.2 - 2025-03-18

### Fixed

* SQL - Fix function `import_csv_add_metadata_column` to avoid error
* SQL - Fix function `import_csv_data_to_target_table`:
  cast input data with target column data type to avoid errors.

## 1.3.1 - 2025-02-19

### Changed

* Fix the filename of the upgrade script for 1.3.0

## 1.3.0 - 2025-02-14

### Changed

* Improve the check for duplicates with a new configuration `duplicate_check_fields`
* Compatibility for the upcoming Lizmap Web Client 3.9.x

### Added

* Allow the user to choose to `UPDATE` the table data with the conflicting data
  from the CSV file. A new checkbox `Update conflicting data` has been added in the form.

### Changed

* Compatibility for Lizmap Web Client 3.7.x & 3.8.x

### Fixed

* Display the localized string in Lizmap Web Client administration panel
  for the right `lizmap.import.from.csv` instead of the
  locale string code

## 1.1.2 - 2024-04-19

### Changed

* Installation - Fix copy of JS & CSS during module configuration

## 1.1.1 - 2024-04-19

### Changed

* Installation - Move JS & CSS file into www/modules-assets/import/


## 1.1.0 - 2024-01-25

### Added

* Installation
  - Install the PostgreSQL schema, tables and functions during module installation
  - Add installation parameter `postgresql_user_group` to give permissions to a dedicated
    PostgreSQL role on the created schema, tables and functions

### Changed

* Add compatibility for Lizmap Web Client 3.7
* CSS - remove old fashion gray background color

## 1.0.1 - 2023-07-17

### Fixed

* bad locale key name of the right name


## 1.0.0 - 2023-03-31

### Added

First version of the import module, which allows to import a CSV
file into a target PostgreSQL layer from the Lizmap application.

See the [README.md](./README.md) file for more details.
