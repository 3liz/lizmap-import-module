<?php

/**
 * @author    3liz
 * @copyright 2011-2019 3liz
 *
 * @see      http://3liz.com
 *
 * @license   Mozilla Public License : http://www.mozilla.org/MPL/
 */
class importModuleUpgrader extends jInstallerModule
{
    public function install()
    {
        // Copy CSS and JS assets
        // We use overwrite to be sure the new versions of the JS files
        // will be used
        $overwrite = true;
        $this->copyDirectoryContent('../www/css', jApp::wwwPath('assets/import/css'), $overwrite);
        $this->copyDirectoryContent('../www/js', jApp::wwwPath('assets/import/js'), $overwrite);
    }
}
