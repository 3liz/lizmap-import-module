<div style="height:100%;overflow:auto;">

    <div class="menu-content">
        <div id="import_tab_div" class="container" style="width:100%;">
            <ul class="nav nav-tabs">
                <li class="active"><a href="#import_form_tab" data-toggle="tab">{@import~import.tab.form.title@}</a></li>
                <li class=""><a href="#import_validation_tab" data-toggle="tab">{@import~import.tab.conformity.title@}</a></li>
                <li class=""><a href="#import_results_tab" data-toggle="tab">{@import~import.tab.result.title@}</a></li>
            </ul>
            <div class="tab-content">
                <div id="import_form_tab" class="tab-pane active">
                    <div class="import_form">
                        {form $form, 'import~service:run', array(), 'htmlbootstrap'}
                        <div>
                            {formcontrols}
                                <p>{ctrl_label}&nbsp;&nbsp;{ctrl_control}</p>
                            {/formcontrols}
                        </div>
                         <div style="margin-top: 30px;">
                            {formsubmit 'check'}{formsubmit 'import'}
                        </div>
                         {/form}
                    </div>
                </div>
                <div id="import_validation_tab" class="tab-pane ">

                    <span id="import_message" style="font-weight: bold;font-size: 1.1em;"></span>

                    <div>
                        <h4>{@import~import.tab.conformity.empty.values@}</h4>
                        <table id="import_validation_not_null" class="table table-condensed table-striped table-bordered">
                            <tr>
                                <th>{@import~import.tab.conformity.label@}</th>
                                <th>{@import~import.tab.conformity.count@}</th>
                                <th>{@import~import.tab.conformity.ids@}</th>
                            </tr>
                            <tr>
                                <td>-</td>
                                <td>-</td>
                                <td>-</td>
                            </tr>
                        </table>
                    </div>

                    <div>
                        <h4>{@import~import.tab.conformity.data.format@}</h4>
                        <table id="import_validation_format" class="table table-condensed table-striped table-bordered">
                            <tr>
                                <th>{@import~import.tab.conformity.label@}</th>
                                <th>{@import~import.tab.conformity.count@}</th>
                                <th>{@import~import.tab.conformity.ids@}</th>
                            </tr>
                            <tr>
                                <td>-</td>
                                <td>-</td>
                                <td>-</td>
                            </tr>
                        </table>
                    </div>

                    <div>
                        <h4>{@import~import.tab.conformity.validity@}</h4>
                        <table id="import_validation_valid" class="table table-condensed table-striped table-bordered">
                            <tr>
                                <th>{@import~import.tab.conformity.label@}</th>
                                <th>{@import~import.tab.conformity.count@}</th>
                                <th>{@import~import.tab.conformity.ids@}</th>
                            </tr>
                            <tr>
                                <td>-</td>
                                <td>-</td>
                                <td>-</td>
                            </tr>
                        </table>
                    </div>
                </div>

                <div id="import_results_tab" class="tab-pane ">

                    <span id="import_message_resultat" style="font-weight: bold;font-size: 1.1em;"></span>

                    <div id="import_errors" style="display:none">
                        <h4>{@import~import.tab.result.errors@}</h4>
                        <table id="import_errors_table" class="table table-condensed table-striped table-bordered">
                            <tr>
                                <th>{@import~import.tab.result.duplicates.count@}</th>
                                <th>{@import~import.tab.result.duplicates.ids@}</th>
                            </tr>
                            <tr>
                                <td id="import_errors_nombre">-</td>
                                <td id="import_errors_ids">-</td>
                            </tr>
                        </table>
                    </div>

                    <div>
                        <h4>{@import~import.tab.result.imported.count@}</h4>
                        <table id="import_results_table" class="table table-condensed table-striped table-bordered">
                            <tr>
                                <th>{@import~import.tab.result.imported.data@}</th>
                            </tr>
                            <tr>
                                <td id="import_results_data">-</td>
                            </tr>
                        </table>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>
