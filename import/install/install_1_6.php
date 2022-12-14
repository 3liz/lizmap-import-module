<?php
/**
 * @author    3liz
 * @copyright 2011-2021 3liz
 *
 * @see      https://3liz.com
 *
 * @license    GPL 3
 */
class importModuleInstaller extends jInstallerModule
{
    public function install()
    {

        // Copy entry point
        // Needed in the upgrade process
        // if the variable $mapping has changed
        $this->createEntryPoint('dav.php', 'config.ini.php');

        if ($this->firstExec('acl2')) {
            $this->useDbProfile('auth');

            // Add right subject
            jAcl2DbManager::addSubject('lizmap.import.from.csv', 'import~jacl2.lizmap.import.from.csv', 'lizmap.grp');

            // Add right on admins group
            jAcl2DbManager::addRight('admins', 'lizmap.import.from.csv');
        }
    }
}
