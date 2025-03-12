CREATE OR REPLACE FUNCTION lizmap_import_module.import_csv_add_metadata_column(
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
            DROP CONSTRAINT IF EXISTS "%1$s_%2$s_import_csv_unique"
            ;
            ALTER TABLE "%1$s"."%2$s"
            ADD CONSTRAINT "%1$s_%2$s_import_csv_unique"
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


CREATE OR REPLACE FUNCTION lizmap_import_module.import_csv_data_to_target_table(
    _temporary_table text,
    _target_schema text,
    _target_table text,
    _target_fields text[],
    _geometry_source text,
    _import_login text,
    _duplicate_check_fields text[])
    RETURNS TABLE(created_id integer)
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
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
    _fields_sql_list = '';
    SELECT INTO _fields_sql_list
        Coalesce(string_agg(concat('"', field, '"'), ', '), '')
    FROM (
        SELECT unnest(_target_fields) AS field
    ) AS fields
    ;

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
    _fields_sql_list = '';
    SELECT INTO _fields_sql_list
        Coalesce(string_agg(concat('s."', column_name, '"::', data_type::text), ', '), '')
    FROM information_schema.columns
    JOIN (
        SELECT unnest(_target_fields) as fields
    ) AS field
        ON column_name = fields
    WHERE table_schema = _target_schema
    AND table_name = _target_table
    ;
    sql_text = sql_text || _fields_sql_list;

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
            FROM "%1$s"."%3$s" AS s
            ON CONFLICT ON CONSTRAINT "%1$s_%2$s_import_csv_unique"
            DO UPDATE
            SET
        $$,
        _target_schema,
        _target_table,
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
$BODY$;


COMMENT ON FUNCTION lizmap_import_module.import_csv_data_to_target_table(text, text, text, text[], text, text, text[])
    IS 'Import the data from the temporary table into the target table';
