<?php

/**
 * @author    3liz
 * @copyright 2011-2019 3liz
 *
 * @see      http://3liz.com
 *
 * @license   Mozilla Public License : http://www.mozilla.org/MPL/
 */
class serviceCtrl extends jController
{
    private $project;
    private $repository;
    private $lizmapProject;
    private $layerName;
    private $layer;
    private $schema;
    private $tableName;
    private $profile;

    /**
     * Check the given parameters are ok.
     *
     * Check that the user can access repository and project.
     * Check that the given layer exists.
     * etc.
     *
     * @param mixed $repository
     * @param mixed $project
     * @param mixed $layerName
     *
     * @return array the array with status (error, success) and message
     */
    private function checkParameters($repository, $project, $layerName)
    {
        if (!\jAcl2::check('lizmap.import.from.csv')) {
            return array('status' => 'error', 'message' => 'No right to use the import CSV module');
        }

        // Check parameters
        if (!$project) {
            return array('status' => 'error', 'message' => 'Project not found');
        }
        if (!$repository) {
            return array('status' => 'error', 'message' => 'Repository not found');
        }
        if (!$layerName) {
            return array('status' => 'error', 'message' => 'Layer name not found');
        }

        // Check project
        $lizmapProject = lizmap::getProject($repository.'~'.$project);
        if (!$lizmapProject) {
            return array('status' => 'error', 'message' => 'A problem occured while loading the project with Lizmap');
        }

        // Check the user can access this project
        if (!$lizmapProject->checkAcl()) {
            return array('status' => 'error', 'message' => jLocale::get('view~default.repository.access.denied'));
        }

        // Set the properties
        $this->repository = $repository;
        $this->project = $project;
        $this->lizmapProject = $lizmapProject;

        // Get the layer instance
        $l = $lizmapProject->findLayerByAnyName($layerName);
        if (!$l) {
            return array('status' => 'error', 'message' => 'Layer '.$layerName.' does not exist');
        }
        $layer = $lizmapProject->getLayer($l->id);

        // Check if layer is a PostgreSQL layer
        if (!($layer->getProvider() == 'postgres')) {
            return array('status' => 'error', 'message' => 'Layer '.$layerName.' is not a PostgreSQL layer');
        }

        // Set the layer property
        $this->layerName = $layerName;
        $this->layer = $layer;

        // Get schema and table names
        $layerParameters = $layer->getDatasourceParameters();
        $schema = $layerParameters->schema;
        $tableName = $layerParameters->tablename;
        if (empty($schema)) {
            $schema = 'public';
        }
        $this->schema = $schema;
        $this->tableName = $tableName;

        // Get layer profile
        $profile = $layer->getDatasourceProfile();
        $this->profile = $profile;

        return array(
            'status' => 'success',
            'message' => 'Parameters OK',
        );
    }

    public function check()
    {
        $rep = $this->getResponse('json');

        // Get parameters
        $project = $this->param('project');
        $repository = $this->param('repository');
        $layerName = $this->param('layername');

        // Check the given parameters
        $result = $this->checkParameters($repository, $project, $layerName);
        if ($result['status'] == 'error') {
            $rep->data = $result;

            return $rep;
        }

        // Check if the import tools exist in the layer database
        $importChecker = new \ImportCsv\ImportHtml($this->profile);
        $result = $importChecker->checkImportCsvInstalled();
        if ($result['status'] == 'error') {
            $rep->data = $result;

            return $rep;
        }
        if (empty($result['data'])) {
            $rep->data = array(
                'status' => 'error',
                'message' => 'The schema lizmap_import_module and the needed table and functions do not exist in the layer database',
            );

            return $rep;
        }

        // Get the import configuration for the given layer
        $result = $importChecker->getTableImportConfiguration($this->schema, $this->tableName, $this->repository, $this->project);
        if ($result['status'] == 'error') {
            $rep->data = $result;

            return $rep;
        }
        if (empty($result['data'])) {
            $rep->data = array(
                'status' => 'error',
                'message' => 'No line returned by the query',
            );

            return $rep;
        }

        // Get the HTML form and return it
        // $feature = $result['data'][0];

        // Return  HTML
        $rep->data = array(
            'status' => 'success',
        );

        return $rep;
    }

    /**
     * Get the import form
     * and return the HTML to load in the sub dock.
     */
    public function getForm()
    {
        /** @var jResponseHtmlfragment $rep */
        $rep = $this->getResponse('htmlfragment');

        // Get parameters
        $project = $this->param('project');
        $repository = $this->param('repository');
        $layerName = $this->param('layername');

        // Check the given parameters
        $result = $this->checkParameters($repository, $project, $layerName);
        if ($result['status'] == 'error') {
            $rep->addContent('<p>'.$result['message'].'</p>');

            return $rep;
        }

        // Get parameters
        $layerName = $this->param('layername');

        $form = jForms::create('import~import');
        $form->setData('repository', $repository);
        $form->setData('project', $project);
        $form->setData('layer_name', $layerName);
        $rep->tplname = 'import';
        $rep->tpl->assign('form', $form);

        return $rep;
    }

    /**
     * Get the data from the import form
     * and return error or data depending on the status.
     */
    public function run()
    {
        // Define the object to return
        $return = array(
            'action' => 'check',
            'status_check' => 0,
            'status_import' => 0,
            'message' => '',
            'data' => array('other' => array()),
        );
        $rep = $this->getResponse('json');

        // Check the right to import
        if (!jAcl2::check('lizmap.import.from.csv')) {
            $return['message'] = jLocale::get('import~import.form.error.right');
            $rep->data = $return;

            return $rep;
        }

        // Get form
        $form = jForms::get('import~import');
        if (!$form) {
            $form = jForms::create('import~import');
        }

        // Automatic form check
        $form->initFromRequest();
        if (!$form->check()) {
            $errors = $form->getErrors();
            $message = \jLocale::get('import~import.form.error.invalid');
            $return['message'] = $message;
            $rep->data = $return;

            return $rep;
        }

        // Get data
        $repository = $form->getData('repository');
        $project = $form->getData('project');
        $layerName = $form->getData('layer_name');

        // Check the given parameters
        $result = $this->checkParameters($repository, $project, $layerName);
        if ($result['status'] == 'error') {
            $rep->data = $result;

            return $rep;
        }

        // Check the file extension and properties
        $ext = strtolower(pathinfo($_FILES['csv']['name'], PATHINFO_EXTENSION));
        if ($ext != 'csv') {
            $return['message'] = \jLocale::get('import~import.form.error.csv.mandatory');
            $rep->data = $return;

            return $rep;
        }

        // Get the CSV file content
        $time = time();
        $csv_target_directory = jApp::varPath('uploads/');
        $csv_target_filename = $time.'_'.$_FILES['csv']['name'];
        $save_file = $form->saveFile('csv', $csv_target_directory, $csv_target_filename);
        if (!$save_file) {
            $return['message'] = \jLocale::get('import~import.form.error.csv.upload.failed');
            $rep->data = $return;

            return $rep;
        }

        // Import library
        $separator = $form->getData('separator');
        $import = new \ImportCsv\ImportManager(
            $repository,
            $project,
            $this->schema,
            $this->tableName,
            $csv_target_directory.'/'.$csv_target_filename,
            $this->profile,
            $separator
        );

        // Check the CSV structure
        list($check, $message) = $import->setConfigurationFromDatabase();
        if (!$check) {
            $return['message'] = $message;
            $rep->data = $return;

            return $rep;
        }

        // Check the CSV structure
        list($check, $message) = $import->checkStructure();
        if (!$check) {
            $return['message'] = $message;
            $rep->data = $return;

            return $rep;
        }

        // Create the temporary tables
        $check = $import->createTemporaryTables();
        if (!$check) {
            $return['message'] = \jLocale::get('import~import.form.error.cannot.create.temp.tables');
            $rep->data = $return;

            return $rep;
        }

        // Import the CSV data into the source temporary table
        list($check, $outputMessage) = $import->saveToSourceTemporaryTable();
        if (!$check) {
            $message = \jLocale::get('import~import.form.error.load.csv.to.temp.tables');
            $message .= "\n";
            $message .= $outputMessage;
            $return['message'] = $message;
            $rep->data = $return;

            return $rep;
        }

        // Import the CSV data into the formatted temporary table
        $check = $import->saveToTargetTemporaryTable();
        if (!$check) {
            $return['message'] = \jLocale::get('import~import.form.error.load.csv.to.temp.tables');
            $rep->data = $return;

            return $rep;
        }

        // Check that the unique id field contains unique values among all records
        $check = $import->checkUniqueIdFieldValues();
        if (!is_array($check) || $check[0]->is_unique == 'error') {
            $return['message'] = \jLocale::get(
                'import~import.csv.mandatory.unique.id.field.not.unique',
                array($check[0]->unique_id_field)
            );
            $rep->data = $return;

            return $rep;
        }

        // Validate the data
        // Check not null
        $check_not_null = $import->validateCsvData('not_null');
        if (!is_array($check_not_null)) {
            $return['message'] = \jLocale::get('import~import.form.error.cannot.check.data.empty.values');
            $rep->data = $return;

            return $rep;
        }

        // Check format
        $check_format = $import->validateCsvData('format');
        if (!is_array($check_format)) {
            $return['message'] = \jLocale::get('import~import.form.error.cannot.check.data.forma');
            $rep->data = $return;

            return $rep;
        }

        // Check validity
        $check_valid = $import->validateCsvData('valid');
        if (!is_array($check_valid)) {
            $return['message'] = \jLocale::get('import~import.form.error.cannot.check.data.conformity');
            $rep->data = $return;

            return $rep;
        }

        // Check if we must import or only validate the data
        $action = $form->getData('check_or_import');
        if (!in_array($action, array('check', 'import'))) {
            $action = 'check';
        }

        $return['data'] = array(
            'not_null' => $check_not_null,
            'format' => $check_format,
            'valid' => $check_valid,
        );

        $return['status_check'] = 1;

        // Only import if it is asked or available for the authenticated user
        // if ($action == 'import' && !jAcl2::check("import.online.access.import")) {
        //     $action = 'check';
        // }

        // If we only check, we can clean the data and return the response
        if ($action == 'check') {
            $return['action'] = 'check';
            jForms::destroy('import~import');
            $import->clean();
            $rep->data = $return;

            return $rep;
        }

        // Go on trying to import the data
        $return['action'] = 'import';

        // We must NOT go on if the check has found some problems
        if (count($check_not_null) || count($check_format) || count($check_valid)) {
            jForms::destroy('import~import');
            $import->clean();
            $return['message'] = \jLocale::get('import~import.form.error.errors.in.conformity.test');
            $rep->data = $return;

            return $rep;
        }

        // Get the logged user login
        $user = \jAuth::getUserSession();
        $login = null;
        if ($user) {
            $login = $user->login;
        }
        if (!$login) {
            jForms::destroy('import~import');
            $import->clean();
            $return['message'] = \jLocale::get('import~import.form.error.cannot.get.authenticated.user.login');
            $rep->data = $return;

            return $rep;
        }

        // Add the needed columns
        // This also adds a unique constraint to the destination table based on duplicate_check_fields content
        $addMetadataColumn = $import->addMetadataColumn();
        if (!is_array($addMetadataColumn) || $addMetadataColumn[0]->import_csv_add_metadata_column == 'f') {
            // Get getDuplicateCheckFields
            $getDuplicateCheckFields = $import->getDuplicateCheckFields();

            // Delete already imported data
            $import->deleteImportedData();
            jForms::destroy('import~import');
            $import->clean();
            $return['message'] = \jLocale::get(
                'import~import.form.error.cannot.add.import.metadata.column',
                array(
                    $this->tableName,
                    implode(', ', $getDuplicateCheckFields),
                )
            );
            $rep->data = $return;

            return $rep;
        }

        // Check for duplicates
        $importType = $import->getImportType();
        if ($importType == 'insert') {
            $check_duplicate = $import->checkCsvDataDuplicatedRecords();
            if (!is_array($check_duplicate)) {
                jForms::destroy('import~import');
                $import->clean();
                $return['message'] = \jLocale::get('import~import.form.error.cannot.check.duplicate.data');
                $rep->data = $return;

                return $rep;
            }
            if ($check_duplicate[0]->duplicate_count > 0) {
                jForms::destroy('import~import');
                $import->clean();
                $message = \jLocale::get(
                    'import~import.form.error.lines.already.in.database',
                    array($check_duplicate[0]->duplicate_count)
                );

                $return['message'] = $message;
                $return['data']['duplicate_count'] = $check_duplicate[0]->duplicate_count;
                $return['data']['duplicate_ids'] = $check_duplicate[0]->duplicate_ids;
                $rep->data = $return;

                return $rep;
            }
        }

        // For update only, check of the CSV unique id field
        // contain values that are in the target table
        // Cancel otherwise
        if ($importType == 'update') {
            $check_ids = $import->checkCsvDataContainsGivenIds();
            if (!is_array($check_ids)) {
                jForms::destroy('import~import');
                $import->clean();
                $return['message'] = \jLocale::get('import~import.form.error.cannot.check.missing.ids');
                $rep->data = $return;

                return $rep;
            }

            if ($check_ids[0]->missing_count > 0) {
                jForms::destroy('import~import');
                $import->clean();
                $message = \jLocale::get(
                    'import~import.form.error.csv.for.update.contains.missing.ids',
                    array($check_ids[0]->missing_count)
                );

                $return['message'] = $message;
                $return['data']['missing_count'] = $check_ids[0]->missing_count;
                $return['data']['missing_ids'] = $check_ids[0]->missing_ids;
                $rep->data = $return;

                return $rep;
            }
        }

        // Import data
        $importData = $import->importCsvIntoTargetTable($login);
        if (!$importData || $importData === null) {
            // Delete already imported data
            $import->deleteImportedData();
            jForms::destroy('import~import');
            $import->clean();
            $return['message'] = \jLocale::get('import~import.form.error.data.import.failure');
            $rep->data = $return;

            return $rep;
        }

        // Add detail in the returned object
        $return['status_import'] = 1;
        $return['data']['records'] = $importData;
        $return['message'] = \jLocale::get('import~import.form.error.data.import.success', array($this->tableName));

        // Clean
        jForms::destroy('import~import');
        $import->clean();

        // Return data
        $rep->data = $return;

        return $rep;
    }
}
