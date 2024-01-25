<?php

/**
 * @author    3liz
 * @copyright 2011-2019 3liz
 *
 * @see      http://3liz.com
 *
 * @license   Mozilla Public License : http://www.mozilla.org/MPL/
 */
class importModuleConfigurator extends \Jelix\Installer\Module\Configurator
{
    public function getDefaultParameters()
    {
        return array(
            'postgresql_user_group' => null,
        );
    }

    public function configure(Jelix\Installer\Module\API\ConfigurationHelpers $helpers)
    {
        // user_group : to which group the write access should be granted on the schema pgrouting
        $this->parameters['postgresql_user_group'] = $helpers->cli()->askInformation(
            'PostgreSQL group of user to grant access on the schema lizmap_import_module ?',
            $this->parameters['postgresql_user_group']
        );

        // Copy CSS and JS files
        $overwrite = true;
        $helpers->copyDirectoryContent('../www/css', jApp::wwwPath('assets/import/css'), $overwrite);
        $helpers->copyDirectoryContent('../www/js', jApp::wwwPath('assets/import/js'), $overwrite);
    }
}
