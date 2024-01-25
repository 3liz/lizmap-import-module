(function () {
    lizMap.events.on({
        'lizmapswitcheritemselected': function (evt) {
            if (evt.selected) {
                let layername = lizMap.getLayerNameByCleanName(evt.name);
                getLayerImportForm(layername);
            }
        }
    });

    /**
     * Get the HTML form to import data for the given layer
     * and add it in the layer sub dock panel.
     *
     * @param {string} layername - The name of the layer
     * @return {string} html - The HTML content with the import form
     */
    async function getLayerImportForm(layername) {
        let options = {
            repository: lizUrls.params.repository,
            project: lizUrls.params.project,
            layername: layername
        };

        // Check if the layer has a import configuration
        let url = importConfig['urls']['check'];
        url = url + '?' + new URLSearchParams(options);
        let hasImport = false;
        await fetch(url).then(function (response) {
            return response.json();
        }).then(function (data) {
            if (data) {
                if (data.status == 'error') {
                    console.log(data.message);
                } else {
                    hasImport = true;
                }
            }
        });

        // Get the Form
        if (hasImport) {
            let url = importConfig['urls']['getForm'];
            url = url + '?' + new URLSearchParams(options);
            await fetch(url).then(function (response) {
                return response.text();
            }).then(function (html) {
                if (html != 'error') {
                    // Add the form in the layer sub panel
                    addFormInLayerSubPanel(html);
                }
            });
        } else {
            document.getElementById('sub-dock').style.width = '';
            document.getElementById('sub-dock').style.maxWidth = '30%';
        }
    }

    /**
     * Add the given HTML to a new tab in the layer sub dock
     *
     * @param {string} html - The HTML content to add in the sub dock
     */
    function addFormInLayerSubPanel(html) {
        if (html) {
            let content = `
                <dt>${importLocales['dock.title']}</dt>
                <dd>
                    <div id="import-csv">${html}</div>
                </dd>
            `;

            // Add content in #sub-dock
            const previousBloc = document.getElementById('import-csv');
            if (previousBloc) previousBloc.remove();
            document.querySelector('#sub-dock div.sub-metadata div.menu-content dl.dl-vertical').insertAdjacentHTML('beforeend', content);

            // Activate the form submit
            onImportFormSubmit();

            // Adapt size
            document.getElementById('sub-dock').style.width = '70vw';
            document.getElementById('sub-dock').style.maxWidth = 'none';
        }
    }

    /**
     * Send the import form data and return promise
     *
     * @param {FormData} formData
     * @return {Promise}
     */
    function sendNewFeatureForm(url, formData) {
        return new Promise(function (resolve, reject) {

            let request = new XMLHttpRequest();
            request.open("POST", url);
            request.onload = function (oEvent) {
                if (request.status == 200) {
                    resolve(request.responseText);
                } else {
                    reject();
                }
            };
            request.send(formData);
        });
    }

    /**
     * Activate the form submit
     * and display the response given by the backend
     *
     */
    function onImportFormSubmit() {
        // Handle form submit
        // First set the check_or_import input data depending on the clicked button
        $('#jforms_import_import input[type="submit"]').on('click', function () {
            let action_input = $('#jforms_import_import input[name="check_or_import"]');
            action_input.val(this.name);
        });
        $('#jforms_import_import').submit(function () {
            $('body').css('cursor', 'wait');
            let form_id = '#jforms_import_import';
            let form = $(form_id);
            let form_data = new FormData(form.get(0));
            let url = form.attr('action');

            // Post data
            let sendFormPromise = sendNewFeatureForm(url, form_data);
            sendFormPromise.then(function (data) {
                $('body').css('cursor', 'auto');
                let response = JSON.parse(data);
                let status_check = (response.status_check == 0) ? 'error' : 'info';
                let action = response.action;

                let criteria_types = ['not_null', 'format', 'valid'];

                let table_header = '';
                table_header += '<tr>';
                table_header += `    <th width="70%">${importLocales['tab.conformity.label']}</th>`;
                table_header += `    <th>${importLocales['tab.conformity.count']}</th>`;
                table_header += `    <th>${importLocales['tab.conformity.ids']}</th>`;
                table_header += '</tr>';
                let empty_html = '';
                empty_html += '<tr>';
                empty_html += '<td>-</td>';
                empty_html += '<td>-</td>';
                empty_html += '<td>-</td>';
                empty_html += '</tr>';

                if (status_check == 'error') {
                    lizMap.addMessage(response.message, status_check, true);
                    for (let c in criteria_types) {
                        let type_criteria = criteria_types[c];
                        $('#import_validation_' + type_criteria).html(table_header + empty_html);
                    }
                    return false;
                }

                // No error, display green message
                if (response.data
                    && response.data.not_null.length == 0
                    && response.data.format.length == 0
                    && response.data.valid.length == 0
                ) {
                    $('#import_message')
                        .html("✅ " + importLocales['form.success.data.validation.success'])
                        .css('color', 'green')
                        ;
                } else {
                    $('#import_message')
                        .html("❗" + importLocales['form.error.errors.in.conformity.test'])
                        .css('color', 'red')
                        ;
                }

                for (let c in criteria_types) {
                    let type_criteria = criteria_types[c];
                    let lines = response.data[type_criteria];
                    let nb_errors = lines.length;
                    let html = '';
                    for (let e in lines) {
                        let error_line = lines[e];
                        let label = (error_line.description !== null && error_line.description != '') ? error_line.description : error_line.label;
                        html += '<tr title="' + label + '">';
                        html += '<td>' + label + '</td>';
                        html += '<td>' + error_line['nb_lines'] + '</td>';
                        html += '<td>' + error_line['ids_text'] + '</td>';
                        html += '</tr>';
                    }

                    $('#import_validation_' + type_criteria).html(table_header + html);
                    $('a[href="#import_validation_tab"]').click();
                }

                if (action == 'import') {
                    let status_import = (response.status_import == 0) ? 'error' : 'info';

                    // import has been tried: open the result tab
                    $('a[href="#import_results_tab"]').click();

                    if (status_import == 'error') {
                        // Add data in the error table
                        if ('duplicate_ids' in response.data) {
                            $('#import_errors_nombre').html(response.data['duplicate_count']);
                            $('#import_errors_ids').html(response.data['duplicate_ids'])
                            $('#import_errors').show();
                            $('a[href="#import_results_tab"]').click();
                        } else {
                            // Display the validation tab
                            $('a[href="#import_validation_tab"]').click();
                        }

                        // Empty the data from the success table
                        $('#import_results_table').html('-');

                        // Display message
                        let msg = response.message;
                        lizMap.addMessage(msg, status_import, true);
                        $('#import_message_result').html("❗" + msg).css('color', 'red');

                    } else {
                        // Empty data in the error table
                        $('#import_errors').hide();
                        $('#import_errors_nombre').html('-');
                        $('#import_errors_ids').html('-');

                        // Add data in the result table
                        $('#import_results_table').html(response.data['records']['nb']);
                        // Display message
                        let msg = importLocales['form.error.data.import.failure'];
                        if (response.data['records']['nb'] > 0) {
                            msg = response.message;
                        }
                        lizMap.addMessage(msg, status_import, true);
                        $('#import_message_result')
                            .html("✅ " + msg)
                            .css('color', 'green')
                            ;

                        // Refresh the layer
                        let layerName = form_data.get('layer_name');
                        let oLayers = lizMap.map.getLayersByName(layerName);
                        if ( oLayers.length > 0 ){
                            oLayers[0].redraw(true);
                        }
                    }

                    return false;
                }
            });

            return false;
        });

        return false;
    }

    return {};
})();
