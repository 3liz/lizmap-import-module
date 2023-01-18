<?php

/**
 * @package   lizmap
 * @subpackage import
 * @author    3liz
 * @copyright 2011-2019 3liz
 * @link      http://3liz.com
 * @license   Mozilla Public License : http://www.mozilla.org/MPL/
 */

class importListener extends jEventListener
{
    public function ongetMapAdditions($event)
    {
        $js = array();
        $jsCode = array();
        $basePath = jApp::urlBasePath();
        $importConfig = array();

        $importConfig['urls']['check'] = jUrl::get('import~service:check');
        $importConfig['urls']['getForm'] = jUrl::get('import~service:getForm');

        $js = array();
        $js[] = $basePath . 'import/js/import.js';
        $css = array();
        $css[] = $basePath . 'import/css/import.css';

        $jsCode = array(
            'var importConfig = ' . json_encode($importConfig) . ';',
        );

        // Add translation
        $locales = $this->getLocales();
        $jsCode[] = 'var importLocales = ' . json_encode($locales) . ';';

        $event->add(
            array(
                'js' => $js,
                'jscode' => $jsCode,
                'css' => $css,
            )
        );
    }

    private function getLocales($lang = null)
    {
        if (!$lang) {
            $lang = jLocale::getCurrentLang() . '_' . jLocale::getCurrentCountry();
        }

        $data = array();
        $path = jApp::getModulePath('import') . 'locales/' . $lang . '/import.UTF-8.properties';
        if (file_exists($path)) {
            $lines = file($path);
            foreach ($lines as $lineNumber => $lineContent) {
                if (!empty($lineContent) and $lineContent != '\n') {
                    $exp = explode('=', trim($lineContent));
                    if (!empty($exp[0])) {
                        $data[$exp[0]] = jLocale::get('import~import.' . $exp[0], null, $lang);
                    }
                }
            }
        }

        return $data;
    }
}
