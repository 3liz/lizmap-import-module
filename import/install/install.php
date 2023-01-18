<?php

/**
 * @package   lizmap
 * @subpackage import
 * @author    3liz
 * @copyright 2011-2019 3liz
 * @link      http://3liz.com
 * @license   Mozilla Public License : http://www.mozilla.org/MPL/
 */
class importModuleInstaller extends \Jelix\Installer\Module\Installer
{
    public function install(Jelix\Installer\Module\API\InstallHelpers $helpers)
    {

        $helpers->database()->useDbProfile('auth');

        $helpers->copyDirectoryContent('www', jApp::wwwPath());


        // Add right subject
        jAcl2DbManager::createRight('lizmap.import.from.csv', 'import~jacl2.lizmap.import.from.csv', 'lizmap.grp');

        // Add right on admins group
        jAcl2DbManager::addRight('admins', 'lizmap.import.from.csv');
    }
}
