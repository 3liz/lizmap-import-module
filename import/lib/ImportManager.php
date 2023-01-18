<?php

/**
 * @package   lizmap
 * @subpackage import
 * @author    3liz
 * @copyright 2011-2019 3liz
 * @link      http://3liz.com
 * @license   Mozilla Public License : http://www.mozilla.org/MPL/
 */

namespace ImportCsv;

/**
 * Contains the tools to import data from CSV files into dedicated tables
 */
class ImportManager
{
    // Lizmap repository key
    protected $repository;

    // Lizmap project key
    protected $project;

    // Jdb profile
    protected $profile;

    // CSV file
    protected $csvFile;

    // CSV separator
    protected $csvSeparator = ',';

    // CSV header
    protected $header;

    // Target table schema
    protected $targetSchema;

    // All possible fields
    protected $targetTable;

    // All possible fields
    protected $targetFields = array();

    // Corresponding fields
    protected $correspondingFields = array();

    // Additional found fields
    protected $additionalFields = array();

    // CSV parsed data
    protected $data;

    // Login
    protected $login;

    // Temporary table to store the content of the CSV file
    protected $temporaryTable;

    // Source of the geometries in the CSV data
    protected $geometrySource = 'wkt';

    // Name of the CSV field containing the unique ids (no necessarily imported)
    protected $uniqueIdField;

    /**
     * Constructor of the import class.
     *
     * @param string $repositoryKey The code of the Lizmap repository
     * @param string $projectKey The code of the QGIS project
     * @param string $csvFile File path of the CSV
     */
    public function __construct($repositoryKey, $projectKey, $targetSchema, $targetTable, $csvFile, $profile)
    {
        // Set the properties
        $this->repository = $repositoryKey;
        $this->project = $projectKey;
        $this->targetSchema = $targetSchema;
        $this->targetTable = $targetTable;
        $this->profile = $profile;
        $this->csvFile = $csvFile;

        // Get the user login
        $login = null;
        $user = \jAuth::getUserSession();
        if ($user) {
            $login = $user->login;
        }
        $this->login = $login;

        // Set the temporary table prefix
        $time = time();
        $this->temporaryTable = 'temp_'.$time;
    }

    /**
     * Get the import configuration for the given target table
     * by querying the PostgreSQL table import_csv_destination_tables
     *
     * @return bool $ok If a valid configuration has been found
     */
    public function setConfigurationFromDatabase()
    {
        $sql = "
        SELECT table_schema, table_name,
        array_to_string(target_fields, ',') AS target_fields,
        geometry_source, unique_id_field
        FROM lizmap_import_module.import_csv_destination_tables
        WHERE True
        AND lizmap_repository = $1
        AND lizmap_project = $2
        AND table_schema = $3
        AND table_name = $4
        LIMIT 1
        ";
        $params = array(
            $this->repository,
            $this->project,
            $this->targetSchema,
            $this->targetTable,
        );
        $data = $this->query($sql, $params);
        $hasData = true;
        if (!is_array($data)) $hasData = false;
        if ($data === null) $hasData = false;
        if (is_array($data) && count($data) == 0) $hasData = false;
        if (!$hasData) {
            return array(
                false,
                \jLocale::get("import~import.csv.no.database.configuration"),
            );
        }

        $this->targetFields = explode(',', $data[0]->target_fields);
        $this->geometrySource = $data[0]->geometry_source;
        $this->uniqueIdField = $data[0]->unique_id_field;

        return array(
            true,
            '',
        );
    }

    /**
     * Runs the needed check on the CSV structure
     *
     * @param string $csv_content Content of the observation CSV file
     */
    public function checkStructure()
    {
        $status = true;
        $message = '';

        // Get the csv header (first line)
        $header = $this->parseCsv(0, 1);

        // Check header
        if (!is_array($header) || count($header) != 1) {
            return array(
                false,
                \jLocale::get("import~import.csv.wrong.header"),
            );
        }
        $header = $header[0];
        $this->header = $header;

        // Check mandatory fields are present
        $missingFields = array();
        foreach ($this->targetFields as $field) {
            if (!in_array($field, $header)) {
                $missingFields[] = $field;
            }
        }

        // Add unique id field in the list of mandatory fields if not present


        // find additional fields and corresponding fields
        $additionalFields = array();
        $correspondingFields = array();
        $hasUniqueIdField = false;
        foreach ($header as $field) {
            if (!in_array($field, $this->targetFields)) {
                $additionalFields[] = $field;
            } else {
                $correspondingFields[] = $field;
            }

            // Check that the unique id field is present
            if ($field == $this->uniqueIdField) {
                $hasUniqueIdField = true;
            }
        }

        // Error when the unique ID field is not found
        if (!$hasUniqueIdField) {
            $message = \jLocale::get("import~import.csv.mandatory.unique.id.field.missing", array($this->uniqueIdField));
            $status = false;
            return array($status, $message);
        }
        if (!in_array($this->uniqueIdField, $correspondingFields)) {
            $correspondingFields[] = $this->uniqueIdField;
        }

        // Add the unique field in the corresponding field
        // so that it is added to the temporary target table
        if (!in_array($this->uniqueIdField, $correspondingFields)) {
            $correspondingFields[] = $this->uniqueIdField;
        }

        // Check geometry fields
        $hasNeededGeometryColumns = false;
        if ($this->geometrySource == 'lonlat' && in_array('longitude', $header) && in_array('latitude', $header)) {
            $hasNeededGeometryColumns = true;
            if (!in_array('longitude', $correspondingFields)) {
                $correspondingFields[] = 'longitude';
            }
            if (!in_array('latitude', $correspondingFields)) {
                $correspondingFields[] = 'latitude';
            }
        }
        else if ($this->geometrySource == 'wkt' && in_array('wkt', $header)) {
            $hasNeededGeometryColumns = true;
            if (!in_array('wkt', $correspondingFields)) {
                $correspondingFields[] = 'wkt';
            }
        }
        if (!$hasNeededGeometryColumns) {
            if ($this->geometrySource == 'lonlat') {
                $neededGeometryFields = array('longitude', 'latitude');
            } else if ($this->geometrySource == 'wkt') {
                $neededGeometryFields = array('wkt');
            }
            $message = \jLocale::get(
                "import~import.csv.mandatory.geometry.fields.missing",
                array(implode(', ', $neededGeometryFields))
            );
            $status = false;
            return array($status, $message);
        }

        // Check that all the required fields are present
        $this->additionalFields = $additionalFields;
        $this->correspondingFields = $correspondingFields;
        if (count($missingFields) > 0) {
            $message = \jLocale::get("import~import.csv.mandatory.fields.missing");
            $message .= ': '.implode(', ', $missingFields);
            $status = false;
            return array($status, $message);
        }

        // Check that the first line (header) contains the same number of columns
        // that the second (data) to avoid errors
        $firstLine = $this->parseCsv(1, 1);
        if (empty($firstLine) || count($firstLine[0]) != count($header)) {
            $message = \jLocale::get("import~import.csv.columns.number.mismatch");
            $status = false;
            return array($status, $message);
        }

        return array($status, $message);
    }

    /**
     * Set the data property
     *
     */
    public function setData()
    {
        // Avoid the first line which contains the CSV header
        $this->data = $this->parseCsv(1);
    }

    /**
     * Parse the CSV raw content and fill the data property
     *
     * @param int $offset Number of lines to avoid from the beginning
     * @param int $limit Number of lines to parse from the beginning. Optional.
     *
     * @return array Array on array containing the data
     */
    protected function parseCsv($offset = 0, $limit = -1)
    {
        $csv_data = array();
        $row = 1;
        $kept = 0;
        if (($handle = fopen($this->csvFile, 'r')) !== FALSE) {
            while (($data = fgetcsv($handle, 1000, $this->csvSeparator)) !== FALSE) {
                // Manage offset
                if ($row > $offset) {
                    // Add data to the table
                    $csv_data[] = $data;
                    $kept++;

                    // Stop after n lines if asked
                    if ($limit > 0 && $kept >= $limit) {
                        break;
                    }
                }
                $row++;
            }
            fclose($handle);
        }
        return $csv_data;
    }

    /**
     * Query the database with SQL text and parameters
     *
     * @param string $sql SQL text to run
     * @param array $params Array of the parameters values
     *
     * @return The resulted data
     */
    private function query($sql, $params)
    {
        \jLog::log('BEGIN ______________________________', 'error');
        \jLog::log(' QUERY SQL ***** = '.$sql, 'error');
        $cnx = \jDb::getConnection($this->profile);
        $cnx->beginTransaction();
        $data = array();
        try {
            $resultset = $cnx->prepare($sql);
            $resultset->execute($params);
            $data = $resultset->fetchAll();
            $cnx->commit();
        } catch (\Exception $e) {
            $cnx->rollback();
            $data = null;
            \jLog::log($e->getMessage(), 'error');
        }

        \jLog::log(' QUERY PARAMS ***** = '.json_encode($params), 'error');
        \jLog::log(' QUERY DATA ***** = '.json_encode($data), 'error');
        \jLog::log('  END ______________________________', 'error');



        return $data;
    }


    /**
     * Create the temporary table in the database
     *
     * @return null|array Not null content if success.
     */
    public function createTemporaryTables()
    {
        $params = array();

        // Drop tables
        $sql = 'DROP TABLE IF EXISTS "'.$this->targetSchema.'"."'.$this->temporaryTable.'_source"';
        $sql .= ', "'.$this->targetSchema.'"."'.$this->temporaryTable.'_target"';
        $params = array();
        $data = $this->query($sql, $params);

        // Create temporary table to store the CSV source data and the formatted imported data
        $tables = array(
            'source' => $this->header,
            'target' => $this->targetFields,
        );
        foreach ($tables as $name => $columns) {
            $sql = 'CREATE TABLE "'.$this->targetSchema.'"."'.$this->temporaryTable.'_'.$name.'" (';
            $sql .= ' temporary_id serial';
            if ($name == 'target') {
                $sql .= ', "'.$this->uniqueIdField.'" text';
                if ($this->geometrySource == 'lonlat') {
                    $sql .= ', "longitude" text';
                    $sql .= ', "latitude" text';
                }
            }
            $comma = ',';
            foreach ($columns as $column) {
                $sql .= $comma.'"'.$column.'" text';
            }
            $sql .= ');';
            $data = $this->query($sql, $params);
            if (!is_array($data) && !$data) {
                return false;
            }
        }

        return true;
    }

    /**
     * Insert the data from the CSV file
     * into the target table.
     *
     * @param string $table Name of the table (include schema eg: my_schema.a_table)
     * @param array $multipleParams Array of array of the parameters values
     *
     * @return boolean True if success
     */
    private function importCsvDataToTemporaryTable($multipleParams)
    {
        $status = true;

        // Insert the CSV data into the source temporary table
        $cnx = \jDb::getConnection($this->profile);
        $cnx->beginTransaction();
        try {
            // Loop through each CSV data line
            foreach ($multipleParams as $params) {
                $sql = ' INSERT INTO "'.$this->targetSchema.'"."'.$this->temporaryTable.'_source"';
                $sql .= ' (';
                $comma = '';
                foreach ($this->header as $column) {
                    $sql .= ' '.$comma.'"'.$column.'"';
                    $comma = ', ';
                }
                $sql .= ' )';
                $sql .= ' VALUES (';
                $comma = '';
                $i = 1;
                foreach ($this->header as $column) {
                    $sql .= $comma.'Nullif(Nullif(trim($'.$i."), ''), 'NULL')";
                    $comma = ', ';
                    $i++;
                }
                $sql .= ');';
                $resultset = $cnx->prepare($sql);
                $resultset->execute($params);
            }
            $cnx->commit();
        } catch (\Exception $e) {
            \jLog::log($e->getMessage());
            $cnx->rollback();
            $status = false;
        }

        return $status;
    }

    /**
     * Save the CSV file content into the temporary table
     *
     * @param string $sql SQL text to run
     * @param array $params Array of the parameters values
     *
     * @return null|array Not null content if success.
     */
    public function saveToSourceTemporaryTable()
    {
        // Read data from the CSV file
        // and set the data property with the read content
        $this->setData();

        // Check the data
        if (count($this->data) == 0) {
            return false;
        }

        // Import the data
        $status = $this->importCsvDataToTemporaryTable($this->data);

        return $status;
    }

    /**
     * Insert the data from the temporary table containing the CSV content
     * into the temporary table with the same structure as the real target table.
     *
     * @return boolean True if success
     */
    private function importCsvDataToTargetTable()
    {
        $status = true;

        // Insert the CSV data into the source temporary table
        $sql = 'INSERT INTO "'.$this->targetSchema.'"."'.$this->temporaryTable.'_target"';
        $sql .= ' (';
        $comma = '';
        $fields = '';

        // Corresponding fields
        foreach ($this->correspondingFields as $column) {
            $fields .= $comma.'"'.$column.'"';
            $comma = ', ';
        }
        $sql .= $fields;
        $sql .= ')';
        $sql .= ' SELECT ';
        $sql .= $fields;

        $sql .= ' FROM "'.$this->targetSchema.'"."'.$this->temporaryTable.'_source"';
        $sql .= ';';

        $params = array();
        $data = $this->query($sql, $params);

        $status = (is_array($data));

        return $status;
    }

    /**
     * Write imported CSV data into the formatted temporary table
     *
     * @return null|array Not null content if success.
     */
    public function saveToTargetTemporaryTable()
    {
        // Insert to the target formatted table
        $status = $this->importCsvDataToTargetTable();

        return $status;
    }

    /**
     * Check that the field configured as unique id field
     * contains unique values in the imported CSV
     *
     * @return null|array Not null content if success.
     */
    public function checkUniqueIdFieldValues()
    {
        $sql = 'SELECT
            CASE
                WHEN count("'.$this->uniqueIdField."\") = count(DISTINCT \"".$this->uniqueIdField."\") THEN 'ok'
                ELSE 'error'
            END AS is_unique,
            $1 AS unique_id_field
        ";
        $sql .= ' FROM "'.$this->targetSchema.'"."'.$this->temporaryTable.'_target"';
        $sql .= ' ';
        $params = array(
            $this->uniqueIdField,
        );
        $data = $this->query($sql, $params);

        return $data;
    }

    /**
     * Validate the CSV imported data against the rules
     * listed in the table import_csv_rules
     *
     * @param string $criteria_type Type de la conformité à tester: not_null, format, valide
     *
     * @return array The list.
     */
    public function validateCsvData($criteria_type)
    {
        $sql = "SELECT *, array_to_string(ids, ', ') AS ids_text";
        $sql .= ' FROM lizmap_import_module.import_csv_check_validity($1, $2, $3, $4, $5)';
        $sql .= ' WHERE nb_lines > 0';
        $sql .= ' ';
        $params = array(
            $this->temporaryTable.'_target',
            $this->targetSchema,
            $this->targetTable,
            $criteria_type,
            $this->uniqueIdField,
        );
        $data = $this->query($sql, $params);

        return $data;
    }

    /**
     * Check that the target temporary table does not have
     * data already present in the target table
     *
     * @return null|array Null if a SQL request has failed, and array with duplicate check data otherwise.
     */
    public function checkCsvDataDuplicatedRecords()
    {
        $sql = "SELECT duplicate_count, duplicate_ids";
        $sql .= " FROM lizmap_import_module.import_csv_check_duplicates(
            $1, $2, $3, string_to_array($4, ','), $5, $6
        )";
        $params = array(
            $this->temporaryTable.'_target',
            $this->targetSchema,
            $this->targetTable,
            implode(',', $this->targetFields),
            $this->geometrySource,
            $this->uniqueIdField,
        );
        $check_duplicate = $this->query($sql, $params);

        return $check_duplicate;
    }

    /**
     * Add the needed import_metadata column in the target table
     *
     * @return null|array Null if a SQL request has failed
     */
    public function addMetadataColumn()
    {
        $sql = "SELECT *";
        $sql .= " FROM lizmap_import_module.import_csv_add_metadata_column($1, $2)";
        $sql .= " WHERE True";

        $params = array(
            $this->targetSchema,
            $this->targetTable,
        );
        $result = $this->query($sql, $params);

        return $result;
    }

    /**
     * Import the CSV imported data in the database
     * target table
     *
     * @param string $login The authenticated user login.
     *
     * @return boolean $status The status of the import.
     */
    public function importCsvIntoTargetTable($login)
    {
        // Import dans la table observation
        $sql = " SELECT count(*) AS nb";
        $sql .= " FROM lizmap_import_module.import_csv_data_to_target_table(
            $1, $2, $3, string_to_array($4, ','), $5, $6
        )
        ";
        $params = array(
            $this->temporaryTable.'_target',
            $this->targetSchema,
            $this->targetTable,
            implode(',', $this->targetFields),
            $this->geometrySource,
            $login,
        );
        $import_data = $this->query($sql, $params);
        if (!is_array($import_data)) {
            return null;
        }
        if (count($import_data) != 1) {
            return null;
        }
        $import_data = $import_data[0];

        return $import_data;
    }


    /**
     * Delete the previously imported data
     * from the different tables.
     *
     *
     * @return boolean $status The status of the import.
     */
    public function deleteImportedData()
    {
        // Delete previously imported data
        $sql = ' SELECT *';
        $sql .= ' FROM lizmap_import_module.import_csv_delete_imported_data($1, $2, $3)';
        $params = array(
            $this->temporaryTable.'_target',
            $this->targetSchema,
            $this->targetTable,
        );
        $result = $this->query($sql, $params);
        if (!is_array($result)) {
            return null;
        }
        if (count($result) != 1) {
            return null;
        }

        return $result;
    }

    /**
     * Clean the import process
     *
     */
    public function clean()
    {
        // Remove CSV file
        unlink($this->csvFile);

        // Drop the temporary table
        $sql = 'DROP TABLE IF EXISTS "'.$this->targetSchema.'"."'.$this->temporaryTable.'_source"';
        $sql .= ', "'.$this->targetSchema.'"."'.$this->temporaryTable.'_target"';
        $params = array();
        $this->query($sql, $params);
    }

    /**
     * Check if a given string is a valid UUID.
     *
     * @param string $uuid The string to check
     *
     * @return bool
     */
    public function isValidUuid($uuid)
    {
        if (empty($uuid)) {
            return false;
        }
        $uuid_regexp = '/^([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})$/i';
        if (!is_string($uuid) || (preg_match($uuid_regexp, $uuid) !== 1)) {
            return false;
        }

        return true;
    }
}
