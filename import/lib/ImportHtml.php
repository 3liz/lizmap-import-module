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

class ImportHtml extends AbstractSearch
{
    /**
     * @var string the jDb profile to use
     */
    protected $dbProfile;

    public function __construct($dbProfile)
    {
        $this->dbProfile = $dbProfile;
    }

    public function checkImportCsvInstalled()
    {
        return $this->doQuery("
            SELECT tablename
            FROM pg_tables
            WHERE schemaname = 'lizmap_import_module'
            AND tablename = 'import_csv_destination_tables'
        ", array(), $this->dbProfile, 'checkImportCsvInstalled');
    }

    /**
     * Check if there is a configuration for the import CSV
     */
    public function getTableImportConfiguration($schema, $tablename, $repository, $project)
    {
        return $this->doQuery("
            SELECT *
            FROM lizmap_import_module.import_csv_destination_tables
            WHERE table_schema = $1
            AND table_name = $2
            AND lizmap_repository = $3
            AND lizmap_project = $4
            LIMIT 1
        ", array(
            $schema,
            $tablename,
            $repository,
            $project,
        ), $this->dbProfile, 'getTableImportConfiguration');
    }
}
