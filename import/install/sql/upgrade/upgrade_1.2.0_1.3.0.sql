ALTER TABLE lizmap_import_module.import_csv_destination_tables
ADD COLUMN IF NOT EXISTS duplicate_check_fields text[];

-- Add the needed column in the target table
DROP FUNCTION IF EXISTS lizmap_import_module.import_csv_add_metadata_column(text, text);
DROP FUNCTION IF EXISTS lizmap_import_module.import_csv_add_metadata_column(text, text, text[]);
CREATE FUNCTION lizmap_import_module.import_csv_add_metadata_column(
    _target_schema text,
    _target_table text,
    _duplicate_check_fields text[]
)
RETURNS BOOL AS $BODY$
DECLARE
    sql_template text;
    sql_text text;
    _var_csv_field text;
    _comma text;
    _duplicate_check_fields_sql_list text;
BEGIN

    BEGIN
        -- Add columns import_metadata
        sql_template = $$
            ALTER TABLE "%1s"."%2s"
            ADD COLUMN IF NOT EXISTS "import_metadata" jsonb
            ;
        $$;
        sql_text = format(sql_template,
            _target_schema,
            _target_table
        );
        EXECUTE sql_text;


        -- Format list of fields used for duplicate check
        _comma = '';
        _duplicate_check_fields_sql_list = '';
        FOR _var_csv_field IN
            SELECT field FROM unnest(_duplicate_check_fields) AS field
        LOOP
            sql_template = '%1$s %2$s';
            _duplicate_check_fields_sql_list = _duplicate_check_fields_sql_list || format(sql_template,
                _comma,
                quote_ident(_var_csv_field)
            );
            _comma = ', ';
        END LOOP;

        -- Create unique index
        sql_template = $$
            ALTER TABLE "%1$s"."%2$s"
            DROP CONSTRAINT IF EXISTS lizmap_import_csv_unique_key
            ;
            ALTER TABLE "%1$s"."%2$s"
            ADD CONSTRAINT lizmap_import_csv_unique_key
            UNIQUE (%3$s);
            ;
        $$;
        sql_text = format(sql_template,
            _target_schema,
            _target_table,
            _duplicate_check_fields_sql_list
        );
        EXECUTE sql_text;

        RETURN TRUE;

    EXCEPTION WHEN others THEN
        RAISE NOTICE '%', SQLERRM;
        -- Log SQL
        RAISE NOTICE '%', sql_text;
        RETURN FALSE;

    END;

    RETURN TRUE;

END;
$BODY$ LANGUAGE plpgsql
;
COMMENT ON FUNCTION lizmap_import_module.import_csv_add_metadata_column(text, text, text[])
IS 'Add a "import_metadata" JSON column to a given tables and unique INDEX to check for duplicates.'
;



-- Check for duplicates
DROP FUNCTION IF EXISTS lizmap_import_module.import_csv_check_duplicates(text, text, text, text[], text, text);
DROP FUNCTION IF EXISTS lizmap_import_module.import_csv_check_duplicates(text, text, text, text[], text);
CREATE FUNCTION lizmap_import_module.import_csv_check_duplicates(
    _temporary_table text,
    _target_schema text,
    _target_table text,
    _duplicate_check_fields text[],
    _unique_id_field text
) RETURNS TABLE (
    duplicate_count integer,
    duplicate_ids text
) AS
$BODY$
DECLARE
    _geometry_columns_record record;
    _target_table_pkeys json;
    _var_csv_field text;
    sql_template TEXT;
    sql_text TEXT;
BEGIN

    -- Get target table SRID (projection id)
    SELECT srid, f_geometry_column
    INTO _geometry_columns_record
    FROM geometry_columns
    WHERE f_table_schema = _target_schema AND f_table_name = _target_table
    ;

    -- Get target table primary key
    _target_table_pkeys = lizmap_import_module.import_csv_get_primary_keys(
        concat('"', _target_schema, '"."', _target_table, '"')
    );

    -- Get the lines already in the target table
    sql_template := '
    WITH source AS (
        SELECT DISTINCT t.%1$s AS ids
        FROM "%2$s"."%3$s" AS t
        INNER JOIN "%4$s"."%5$s" AS o
        ON (
            TRUE
    ';
    sql_text = format(sql_template,
        quote_ident(_unique_id_field),
        _target_schema,
        _temporary_table,
        _target_schema,
        _target_table
    );

    -- Add equality checks to search for duplicates
    FOR _var_csv_field IN
        SELECT field FROM unnest(_duplicate_check_fields) AS field
    LOOP
        sql_template = $$
            AND Coalesce(t."%1$s"::text, '') = Coalesce(o."%1$s"::text, '')
        $$;
        sql_text = sql_text || format(sql_template,
            _var_csv_field
        );
    END LOOP;

    sql_template = $$
        )
        WHERE o.%1$s IS NOT NULL
    $$;
    sql_text = sql_text || format(sql_template,
        quote_ident(_target_table_pkeys->0->>'field_name')
    );

    -- Count results
    sql_text =  sql_text || $$
        )
        SELECT
            count(ids)::integer AS duplicate_count,
            string_agg(ids::text, ', ' ORDER BY ids) AS duplicate_ids
        FROM source
    $$;

    RAISE NOTICE '%', sql_text;

    BEGIN
        -- On récupère les données
        RETURN QUERY EXECUTE sql_text;
    EXCEPTION WHEN others THEN
        RAISE NOTICE '%', SQLERRM;
        RAISE NOTICE '%' , sql_text;
        RETURN QUERY SELECT 0 AS duplicate_count, '' AS duplicate_ids;
    END;

END
$BODY$
LANGUAGE plpgsql VOLATILE
COST 100
;

COMMENT ON FUNCTION lizmap_import_module.import_csv_check_duplicates(text, text, text, text[], text)
IS 'Check for duplicated data between the CSV source data and the target tables.
It uses the configuration stored in the column "duplicate_check_fields" of the table "import_csv_destination_tables"'
;


-- Import the data from the temporary table to the target table
DROP FUNCTION IF EXISTS lizmap_import_module.import_csv_data_to_target_table(text, text, text, text[], text, text);
DROP FUNCTION IF EXISTS lizmap_import_module.import_csv_data_to_target_table(text, text, text, text[], text, text, text[]);
CREATE FUNCTION lizmap_import_module.import_csv_data_to_target_table(
    _temporary_table text,
    _target_schema text,
    _target_table text,
    _target_fields text[],
    _geometry_source text,
    _import_login text,
    _duplicate_check_fields text[]
)
RETURNS TABLE (
    created_id integer
) AS
$BODY$
DECLARE
    sql_template TEXT;
    sql_text TEXT;
    _var_csv_field text;
    _target_table_pkeys json;
    _comma TEXT;
    _fields_sql_list text;
    _duplicate_check_fields_sql_list text;
    _geometry_columns_record record;
BEGIN

    -- Get target table SRID (projection id)
    SELECT srid, f_geometry_column
    INTO _geometry_columns_record
    FROM geometry_columns
    WHERE f_table_schema = _target_schema AND f_table_name = _target_table
    ;

    -- Get target table primary key
    _target_table_pkeys = lizmap_import_module.import_csv_get_primary_keys(
        concat('"', _target_schema, '"."', _target_table, '"')
    );

    -- List of fields for SQL
    _comma = '';
    _fields_sql_list = '';
    FOR _var_csv_field IN
        SELECT field FROM unnest(_target_fields) AS field
    LOOP
        sql_template = '%1$s "%2$s"';
        _fields_sql_list = _fields_sql_list || format(sql_template,
            _comma,
            _var_csv_field
        );
        _comma = ', ';
    END LOOP;

    -- geometry
    IF _geometry_source = 'lonlat' THEN
        _fields_sql_list = _fields_sql_list || format(
            ', "%1$s" ',
            quote_ident(_geometry_columns_record.f_geometry_column)
        );
    END IF;

    -- Build the INSERT SQL
    sql_text = '';
    sql_template := $$
        INSERT INTO "%1$s"."%2$s" AS t
        (
    $$;
    sql_text = sql_text || format(sql_template,
        _target_schema,
        _target_table
    );

    -- List of fields
    sql_text = sql_text || _fields_sql_list;

    -- import metadata
    sql_text = sql_text || ', "import_metadata" ';

    sql_text = sql_text || $$
        )
        SELECT
    $$;

    -- Values from the temporary table
    _comma = '';
    FOR _var_csv_field IN
        SELECT field FROM unnest(_target_fields) AS field
    LOOP
        sql_template = '%1$s s.%2$s';
        sql_text = sql_text || format(sql_template,
            _comma,
            quote_ident(_var_csv_field)
        );
        _comma = ', ';
    END LOOP;

    -- geometry value
    IF _geometry_source = 'lonlat' THEN
        sql_template = $$
            ,
            CASE
                WHEN
                    lizmap_import_module.import_csv_is_given_type(s.longitude, 'real')
                    AND lizmap_import_module.import_csv_is_given_type(s.latitude, 'real')
                    AND s.longitude IS NOT NULL
                    AND s.latitude IS NOT NULL
                THEN
                    ST_Transform(
                        ST_SetSRID(
                            ST_MakePoint(s.longitude::real, s.latitude::real),
                            %1$s
                        ),
                        %1$s
                    )
                ELSE NULL
            END
        $$;
        sql_text = sql_text || format(sql_template,
            _geometry_columns_record.srid
        );
    END IF;

    -- _duplicate_check_fields_sql_list
    _comma = '';
    _duplicate_check_fields_sql_list = '';
    FOR _var_csv_field IN
        SELECT field FROM unnest(_duplicate_check_fields) AS field
    LOOP
        sql_template = '%1$s s."%2$s"';
        _duplicate_check_fields_sql_list = _duplicate_check_fields_sql_list || format(sql_template,
            _comma,
            _var_csv_field
        );
        -- concatenate to have something like "field_1", '@', "field_2"
        _comma = $$, '@', $$;
    END LOOP;

    -- import metadata
    sql_text = sql_text || format(
        $$
            ,
            json_build_object(
                'import_login', '%1$s',
                'import_temp_table', '%2$s',
                'import_time', now()::timestamp(0),
                'action', 'I'
        ) AS import_metadata
        $$,
        _import_login,
        _temporary_table,
        _duplicate_check_fields_sql_list
    );

    -- If the data is already there, update
    sql_text = sql_text || format(
        $$
            FROM "%1$s"."%2$s" AS s
            ON CONFLICT ON CONSTRAINT lizmap_import_csv_unique_key
            DO UPDATE
            SET
        $$,
        _target_schema,
        _temporary_table
    );

    -- UPSERT List of fields
    _comma = '';
    FOR _var_csv_field IN
        SELECT field FROM unnest(_target_fields) AS field
    LOOP
        sql_template = '%1$s "%2$s" = EXCLUDED."%2$s"';
        sql_text = sql_text || format(sql_template,
            _comma,
            _var_csv_field
        );
        _comma = ', ';
    END LOOP;

    -- UPSERT geometry
    IF _geometry_source = 'lonlat' THEN
        sql_text = sql_text || format(
            ', "%1$s" = EXCLUDED."%1$s"',
            quote_ident(_geometry_columns_record.f_geometry_column)
        );
    END IF;

    -- UPSERT import metadata
    sql_text = sql_text ||
        $$
            ,
            "import_metadata" = (
                jsonb_set(
                    EXCLUDED."import_metadata"::jsonb,
                    '{action}',
                    '"U"'
                )
            )::jsonb
        $$
    ;

    -- return the primary keys inserted or modified
    sql_text = sql_text || format(
        $$
            RETURNING "%1$s"
        $$,
        _target_table_pkeys->0->>'field_name'
    );

    RAISE NOTICE '%', sql_text;

    -- Import data
    RETURN QUERY EXECUTE sql_text;

END
$BODY$
LANGUAGE plpgsql VOLATILE
COST 100
;

COMMENT ON FUNCTION lizmap_import_module.import_csv_data_to_target_table(text, text, text, text[], text, text, text[])
IS 'Import the data from the temporary table into the target table'
;
