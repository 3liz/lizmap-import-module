<?php

/**
 * @package   lizmap
 * @subpackage import
 * @author    3liz
 * @copyright 2011-24 3liz
 * @link      http://3liz.com
 * @license   Mozilla Public License : http://www.mozilla.org/MPL/
 */
require_once __DIR__.'/importDBInstallTrait.php';

class importModuleUpgrader_1_2_0__1_3_0 extends \Jelix\Installer\Module\Installer
{
    use importDBInstallTrait;

    public $targetVersions = array(
        '1.3.0',
    );

    public $date = '2025-02-14';

    function install(Jelix\Installer\Module\API\InstallHelpers $helpers)
    {
        $helpers->database()->useDbProfile('auth');

        // Get SQL template file
        $sql_file = $this->getPath().'install/sql/upgrade/upgrade_1.2.0_1.3.0.sql';
        $sql = jFile::read($sql_file);
        $db = $helpers->database()->dbConnection();
        $db->exec($sql);

        // Grant rights to the created schema
        $this->launchGrantIntoDb($db);
    }
}
