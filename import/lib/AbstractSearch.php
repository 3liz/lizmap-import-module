<?php

/**
 * @package   lizmap
 * @subpackage import
 * @author    3liz
 * @copyright 2011-2019 3liz
 * @link      http://3liz.com
 * @license   Mozilla Public License : http://www.mozilla.org/MPL/
 */

namespace ImportCsv;

abstract class AbstractSearch
{
    protected function query($sql, $filterParams, $profile)
    {
        if ($profile) {
            $cnx = \jDb::getConnection($profile);
        } else {
            // Default connection
            $cnx = \jDb::getConnection();
        }

        $resultset = $cnx->prepare($sql);
        if (empty($filterParams)) {
            $resultset->execute();
        } else {
            $resultset->execute($filterParams);
        }

        return $resultset;
    }

    protected function doQuery($sql, $filterParams, $profile, $queryName)
    {
        try {
            $result = $this->query($sql, $filterParams, $profile);
        } catch (\Exception $e) {
            return array(
                'status' => 'error',
                'code' => 1,
                'message' => 'Error at the query concerning ' . $queryName,
            );
        }

        if (!$result) {
            return array(
                'status' => 'error',
                'code' => 2,
                'message' => 'Error at the query concerning ' . $queryName,
            );
        }

        return array(
            'status' => 'success',
            'code' => 0,
            'data' => $result->fetchAll(),
        );
    }
}
