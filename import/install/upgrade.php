<?php

/**
 * @author    3liz
 * @copyright 2011-2019 3liz
 *
 * @see      http://3liz.com
 *
 * @license   Mozilla Public License : http://www.mozilla.org/MPL/
 */
class importModuleUpgrader extends \Jelix\Installer\Module\Installer
{
    public function install(Jelix\Installer\Module\API\InstallHelpers $helpers)
    {
        // Copy CSS and JS assets
        // We use overwrite to be sure the new versions of the JS files
        // will be used
        $overwrite = true;
        $helpers->copyDirectoryContent('../www/css', jApp::wwwPath('modules-assets/import/css'), $overwrite);
        $helpers->copyDirectoryContent('../www/js', jApp::wwwPath('modules-assets/import/js'), $overwrite);
    }
}
