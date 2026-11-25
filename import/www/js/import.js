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
     * Check if Lizmap uses Bootstrap 5 (Lizmap 3.10 and above) or Bootstrap 2 (before).
     *
     * Bootstrap 5 is loaded as a script which defines the global object bootstrap.
     *
     * @return {boolean} True for Bootstrap 5
     */
    function isBootstrap5() {
        return typeof window.bootstrap !== 'undefined' && typeof window.bootstrap.Tab !== 'undefined';
    }

    /**
     * Adapt the tabs of the import form, written for Bootstrap 2, to Bootstrap 5.
     *
     * With Bootstrap 2 (before Lizmap 3.10), nothing is changed. With Bootstrap 5, the links of the tabs
     * get the class nav-link and the attribute data-bs-toggle, the active tab is marked on its link,
     * and the container gets the class import-bs5 used by the CSS of the flat style of Lizmap.
     *
     * @param {HTMLElement} container - The element containing the ul.nav-tabs and the div.tab-pane
     */
    function adaptTabs(container) {
        if (!container || !isBootstrap5()) {
            return;
        }
        container.classList.add('import-bs5');
        for (const item of container.querySelectorAll('ul.nav-tabs > li')) {
            const link = item.querySelector('a');
            item.classList.add('nav-item');
            link.classList.add('nav-link');
            link.setAttribute('data-bs-toggle', 'tab');
            link.removeAttribute('data-toggle');
            if (item.classList.contains('active')) {
                link.classList.add('active');
                item.classList.remove('active');
            }
        }
    }

    /**
     * Display a tab of the import form, with Bootstrap 5 or Bootstrap 2.
     *
     * @param {string} target - The id of the tab pane, like #import_results_tab
     */
    function showTab(target) {
        const link = document.querySelector(`#import_tab_div ul.nav-tabs a[href="${target}"]`);
        if (!link) {
            return;
        }
        if (isBootstrap5()) {
            window.bootstrap.Tab.getOrCreateInstance(link).show();
        } else {
            $(link).tab('show');
        }
    }

    /**
     * Redraw a layer of the map, so that it displays the imported data.
     *
     * Same method as the edition of Lizmap 3.9 and 3.10 (redrawLayerSource in edition.js): the layer states
     * of mainLizmap.state have no method to reload a layer, so the OpenLayers layer is taken from the map,
     * which also handles the layers grouped in a single WMS image. A parameter is changed for a WMS source,
     * so that the browser does not answer from its cache.
     *
     * @param {string} layerName - The name of the layer
     */
    function redrawLayer(layerName) {
        const olLayer = lizMap.mainLizmap.map.getLayerByName(layerName);
        if (!olLayer) {
            return;
        }
        const source = olLayer.getSource();
        if (typeof source.updateParams === 'function') {
            source.updateParams({ 'LIZMAP_REDRAW': Date.now() });
        } else if (typeof source.refresh === 'function') {
            source.refresh();
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

            // Add content in the list of the layer information of the sub-dock:
            // with the class dl-vertical before Lizmap 3.10, without it after
            const previousBloc = document.getElementById('import-csv');
            if (previousBloc) previousBloc.remove();
            const layerInformation = document.querySelector('#sub-dock div.sub-metadata div.menu-content > dl');
            if (!layerInformation) {
                return;
            }
            layerInformation.insertAdjacentHTML('beforeend', content);

            // Tabs with Bootstrap 5 and the flat style of Lizmap 3.10 and above
            adaptTabs(document.getElementById('import_tab_div'));

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
                    showTab('#import_validation_tab');
                }

                if (action == 'import') {
                    let status_import = (response.status_import == 0) ? 'error' : 'info';

                    // import has been tried: open the result tab
                    showTab('#import_results_tab');

                    if (status_import == 'error') {
                        // Add data in the error table
                        if ('duplicate_ids' in response.data || 'missing_ids' in response.data) {
                            if ('duplicate_ids' in response.data) {
                                $('#import_errors_nombre').html(response.data['duplicate_count']);
                                $('#import_errors_ids').html(response.data['duplicate_ids'])
                            } else {
                                $('#import_errors_missing_count').html(response.data['missing_count']);
                                $('#import_errors_missing_ids').html(response.data['missing_ids'])
                            }
                            $('#import_errors').show();
                            showTab('#import_results_tab');
                        } else {
                            // Display the validation tab
                            showTab('#import_validation_tab');
                        }

                        // Empty the data from the success table
                        $('#import_results_data').html('-');

                        // Display message
                        let msg = response.message;
                        lizMap.addMessage(msg, status_import, true);
                        $('#import_message_resultat').html("❗" + msg).css('color', 'red');

                    } else {
                        // Empty data in the error table
                        $('#import_errors').hide();
                        $('#import_errors_nombre').html('-');
                        $('#import_errors_ids').html('-');
                        $('#import_errors_missing_count').html('-');
                        $('#import_errors_missing_ids').html('-');

                        // Add data in the result table
                        $('#import_results_data').html(response.data['records']['nb']);
                        // Display message
                        let msg = importLocales['form.error.data.import.failure'];
                        if (response.data['records']['nb'] > 0) {
                            msg = response.message;
                        }
                        lizMap.addMessage(msg, status_import, true);
                        $('#import_message_resultat')
                            .html("✅ " + msg)
                            .css('color', 'green')
                            ;

                        // Redraw the layer to display the imported data
                        redrawLayer(form_data.get('layer_name'));
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
