<?php

/**
 * @author    3Liz
 * @copyright 2023 3Liz
 *
 * @see       https://3liz.com
 *
 * @license   Mozilla Public License : http://www.mozilla.org/MPL/
 */
require_once __DIR__ . '/importDBInstallTrait.php';

class importModuleInstaller extends \Jelix\Installer\Module\Installer
{
    use importDBInstallTrait;

    public function install(Jelix\Installer\Module\API\InstallHelpers $helpers)
    {
        $helpers->database()->useDbProfile('auth');

        // Get SQL template file
        $sql_file = $this->getPath() . 'install/sql/install.pgsql.sql';
        $sql = jFile::read($sql_file);
        $db = $helpers->database()->dbConnection();
        $db->exec($sql);

        // Grant rights to the created schema
        $this->launchGrantIntoDb($db);

        // Copy CSS and JS assets
        // We use overwrite to be sure the new versions of the JS files
        // will be used
        $overwrite = true;
        $helpers->copyDirectoryContent('../www/css', jApp::wwwPath('assets/import/css'), $overwrite);
        $helpers->copyDirectoryContent('../www/js', jApp::wwwPath('assets/import/js'), $overwrite);

        // Add right subject
        jAcl2DbManager::createRight('lizmap.import.from.csv', 'import~jacl2.lizmap.import.from.csv', 'lizmap.grp');

        // Add right on admins group
        jAcl2DbManager::addRight('admins', 'lizmap.import.from.csv');
    }
}
