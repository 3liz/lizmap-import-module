<?php
/**
 * @author    3liz
 * @copyright 2011-2021 3liz
 *
 * @see      https://3liz.com
 *
 * @license    GPL 3
 */
class importModuleInstaller extends \Jelix\Installer\Module\Installer
{
    public function install(Jelix\Installer\Module\API\InstallHelpers $helpers)
    {

        $helpers->database()->useDbProfile('auth');

        // Add right subject
        jAcl2DbManager::addSubject('lizmap.import.from.csv', 'import~jacl2.lizmap.import.from.csv', 'lizmap.grp');

        // Add right on admins group
        jAcl2DbManager::addRight('admins', 'lizmap.import.from.csv');
    }
}
