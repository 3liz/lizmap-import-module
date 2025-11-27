CREATE SCHEMA IF NOT EXISTS lizmap_import_module;

-- Import CSV destination tables
CREATE TABLE IF NOT EXISTS lizmap_import_module.import_csv_destination_tables (
    id serial primary key NOT NULL,
    table_schema text NOT NULL,
    table_name text NOT NULL,
    lizmap_repository text NOT NULL,
    lizmap_project text NOT NULL,
    import_type text NOT NULL DEFAULT 'insert',
    target_fields text[] NOT NULL,
    geometry_source text NOT NULL,
    unique_id_field text NOT NULL,
    duplicate_check_fields text[] NOT NULL,
    CONSTRAINT import_csv_destination_tables_import_type_valid CHECK (import_type IN ('insert', 'update', 'upsert')),
    CONSTRAINT import_csv_destination_tables_geometry_source_valid CHECK (geometry_source IN ('none', 'lonlat', 'wkt')),
    CONSTRAINT import_csv_destination_tables_unique UNIQUE (table_schema, table_name, lizmap_repository, lizmap_project)
);
COMMENT ON TABLE lizmap_import_module.import_csv_destination_tables
IS 'List all the tables for which data can be imported from CSV files'
;

COMMENT ON COLUMN lizmap_import_module.import_csv_destination_tables.import_type
IS 'Defines the type of import allowed :
* insert = only new data,
* update = only update based on given unique_id_field
* upsert = insert new data & update data on conflict based on duplicate_check_fields'
;


-- Rules to validate the fields values
CREATE TABLE IF NOT EXISTS lizmap_import_module.import_csv_field_rules (
    id serial not null PRIMARY KEY,
    target_table_schema text NOT NULL,
    target_table_name text NOT NULL,
    lizmap_repository text,
    lizmap_project text,
    criteria_type text NOT NULL,
    code text NOT NULL,
    label text NOT NULL,
    description text,
    condition text NOT NULL,
    join_table text,
    CONSTRAINT import_csv_field_rules_unique_code UNIQUE (target_table_schema, target_table_name, code),
    CONSTRAINT import_csv_field_rules_criteria_type_valid CHECK (criteria_type IN ('not_null', 'format', 'valid'))
);

COMMENT ON TABLE lizmap_import_module.import_csv_field_rules
IS 'List of rules used to validate the format of data'
;


-- Get a table regclass corresponding schema and table
DROP FUNCTION IF EXISTS lizmap_import_module.import_csv_get_regclass_properties(regclass);
CREATE FUNCTION lizmap_import_module.import_csv_get_regclass_properties(_source_table regclass)
RETURNS json AS $BODY$
DECLARE infos json;
BEGIN
    SELECT json_build_object(
        'schema_name', nspname,
        'table_name', relname
    ) INTO infos
    FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS ns
    ON c.relnamespace = ns.oid
    WHERE c.oid = _source_table
    LIMIT 1
    ;

    RETURN infos;

END;
$BODY$ LANGUAGE plpgsql
;
COMMENT ON FUNCTION lizmap_import_module.import_csv_get_regclass_properties(regclass)
IS 'Get a table regclass corresponding schema and table'
;

-- Add the needed column in the target table
DROP FUNCTION IF EXISTS lizmap_import_module.import_csv_add_metadata_column(text, text);
DROP FUNCTION IF EXISTS lizmap_import_module.import_csv_add_metadata_column(text, text, text[]);
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



-- Get the primary key fields name and data type for a given table
DROP FUNCTION IF EXISTS lizmap_import_module.import_csv_get_primary_keys(regclass);
CREATE FUNCTION lizmap_import_module.import_csv_get_primary_keys(_target_table regclass)
RETURNS json AS $BODY$
DECLARE primary_keys json;
BEGIN
    SELECT INTO primary_keys
        json_agg(
            json_build_object(
                'field_name', a.attname,
                'data_type', format_type(a.atttypid, a.atttypmod)
            )
        )
    FROM pg_index i
    JOIN pg_attribute a
        ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
    WHERE i.indrelid = _target_table
    AND i.indisprimary;

    RETURN primary_keys;
END;
$BODY$ LANGUAGE plpgsql
;
COMMENT ON FUNCTION lizmap_import_module.import_csv_get_primary_keys(regclass)
IS 'Get the primary key fields name and data type for a given table';


-- Check if a field value corresponds to the given type
DROP FUNCTION IF EXISTS lizmap_import_module.import_csv_is_given_type(text, text);
CREATE OR REPLACE FUNCTION lizmap_import_module.import_csv_is_given_type(s text, t text)
RETURNS BOOLEAN AS $BODY$
BEGIN
    -- Avoid to test empty strings
    s = Nullif(s, '');
    IF s IS NULL THEN
        return true;
    END IF;

    -- Test to cast the string to the given type
    IF t = 'date' THEN
        PERFORM s::date;
        RETURN true;
    ELSIF t = 'time' THEN
        PERFORM s::time;
        RETURN true;
    ELSIF t = 'timestamp' THEN
        PERFORM CAST(s AS timestamp);
        RETURN true;
    ELSIF t = 'integer' THEN
        PERFORM s::integer;
        RETURN true;
    ELSIF t = 'real' THEN
        PERFORM s::real;
        RETURN true;
    ELSIF t = 'text' THEN
        PERFORM s::text;
        RETURN true;
    ELSIF t = 'boolean' THEN
        PERFORM s::boolean;
        RETURN true;
    ELSIF t = 'uuid' THEN
        PERFORM s::uuid;
        RETURN true;
    ELSIF t = 'wkt' THEN
        PERFORM (ST_GeomFromText(s))::geometry;
        RETURN true;
    ELSE
        RETURN true;
    END IF;
EXCEPTION WHEN others THEN
    return false;
END;
$BODY$ LANGUAGE plpgsql
;

COMMENT ON FUNCTION lizmap_import_module.import_csv_is_given_type(text, text)
IS 'Test if the content of a field has the expected type. It returns True if we can cast the value into the expected data type.
This function can be extended to user defined data types if necessary'
;

-- Check the validity of all the field values inside the given table
DROP FUNCTION IF EXISTS lizmap_import_module.import_csv_check_validity(text, text, text, text, text);
DROP FUNCTION IF EXISTS lizmap_import_module.import_csv_check_validity(text, text, text, text, text, text, text);
CREATE FUNCTION lizmap_import_module.import_csv_check_validity(
    _temporary_table text,
    _target_schema text,
    _target_table text,
    _lizmap_repository text,
    _lizmap_project text,
    _criteria_type text,
    _unique_id_field text
)
RETURNS TABLE (
    id_criteria text,
    code text,
    label text,
    description text,
    condition text,
    nb_lines integer,
    ids text[]
) AS
$BODY$
DECLARE var_id_criteria INTEGER;
DECLARE var_code TEXT;
DECLARE var_label TEXT;
DECLARE var_description TEXT;
DECLARE var_condition TEXT;
DECLARE var_join_table TEXT;
DECLARE sql_template TEXT;
DECLARE sql_text TEXT;
DECLARE rec record;

BEGIN

    -- Create temporary table to store the results
    CREATE TEMPORARY TABLE temp_results (
        id_criteria text,
        code text,
        label text,
        description text,
        condition text,
        nb_lines integer,
        ids text[]
    ) ON COMMIT DROP
    ;

    -- Get

    -- Loop for each criteria
    FOR var_id_criteria, var_code, var_label, var_description, var_condition, var_join_table IN
        SELECT c.id AS id_criteria, c.code, c.label, c.description, c.condition, c.join_table
        FROM lizmap_import_module.import_csv_field_rules AS c
        WHERE criteria_type = _criteria_type
        AND target_table_schema = _target_schema::text
        AND target_table_name = _target_table::text
        AND (lizmap_repository = _lizmap_repository::text OR lizmap_repository IS NULL)
        AND (lizmap_project = _lizmap_project::text OR lizmap_project IS NULL)
        ORDER BY c.id

    LOOP
        BEGIN
            sql_template := '
            INSERT INTO temp_results
            SELECT
                %s AS id_criteria, %s AS code,
                %s AS label, %s AS description,
                %s AS condition,
                count(o."%s") AS nb_lines,
                array_agg(o."%s") AS ids
            FROM "%s"."%s" AS o
            ';
            sql_text := format(
                sql_template,
                var_id_criteria, quote_literal(var_code),
                quote_literal(var_label), quote_nullable(var_description),
                quote_literal(var_condition),
                _unique_id_field,
                _unique_id_field,
                _target_schema,
                _temporary_table
            );

            -- optionally add the JOIN clause
            IF var_join_table IS NOT NULL THEN
                sql_template := '
                , %s AS t
                ';
                sql_text := sql_text || format(
                    sql_template,
                    var_join_table
                );
            END IF;

            -- Condition du critère
            sql_template :=  '
            WHERE True
            -- condition
            AND NOT (
                %s
            )
            ';
            sql_text := sql_text || format(sql_template, var_condition);

            -- On récupère les données
            EXECUTE sql_text;
        EXCEPTION WHEN others THEN
            RAISE NOTICE '%', concat(var_code, ': ' , var_label, '. Description: ', var_description);
            RAISE NOTICE '%', SQLERRM;
            -- Log SQL
            RAISE NOTICE '%' , sql_text;
        END;

    END LOOP;

    RETURN QUERY SELECT * FROM temp_results;

END
$BODY$
LANGUAGE plpgsql VOLATILE
COST 100
;

COMMENT ON FUNCTION lizmap_import_module.import_csv_check_validity(text, text, text, text, text, text, text)
IS 'Check the validity of the source data against the rules from the table import_csv_field_rules'
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
CREATE OR REPLACE FUNCTION lizmap_import_module.import_csv_data_to_target_table(
    _temporary_table text,
    _target_schema text,
    _target_table text,
    _target_fields text[],
    _geometry_source text,
    _import_login text,
    _import_type text,
    _unique_id_field text)
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
    _geometry_columns_record record;
    _some_text text;
    _update_when_needed text;
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

    -- for UPDATE
    -- We need to add the "_unique_id_field" because it is used in the WHERE clause
    -- We add it only if it is not already in the target_fields parameter
    IF _import_type = 'update' AND NOT _unique_id_field = ANY (_target_fields)
    THEN
        _target_fields = array_append(_target_fields, _unique_id_field);
    END IF;

    -- List of fields for SQL
    _fields_sql_list = '';
    SELECT INTO _fields_sql_list
        Coalesce(string_agg(concat('t."', field, '"'), ', '), '')
    FROM (
        SELECT unnest(_target_fields) AS field
    ) AS fields
    ;

    -- geometry
    IF _geometry_source IN ('lonlat', 'wkt') THEN
        _fields_sql_list = _fields_sql_list || format(
            ', t."%1$s" ',
            quote_ident(_geometry_columns_record.f_geometry_column)
        );
    END IF;

    -- Build the INSERT SQL
    sql_text = '';

    IF _import_type IN ('insert', 'upsert') THEN
        -- INSERT or UPSERT
        sql_template := $$
            INSERT INTO "%1$s"."%2$s" AS t
            (
        $$;
    ELSE
        -- UPDATE
        sql_template := $$
            UPDATE "%1$s"."%2$s" AS t
            SET (
        $$;
    END IF;

    sql_text = sql_text || format(sql_template,
        _target_schema,
        _target_table
    );

    -- List of fields
    _some_text = '';

    _some_text = _some_text || _fields_sql_list;

    -- import metadata
    _some_text = _some_text || ', "import_metadata" ';

    -- add the list of fields
    sql_text = sql_text || replace(_some_text, 't.', '');

    -- Adapt SQL depending on the import type
    IF _import_type IN ('insert', 'upsert') THEN
        sql_text = sql_text || $$
            )
            SELECT
        $$;
    ELSE
        sql_text = sql_text || format(
            $$
                ) = (
                    %1$s
                )
                FROM (
                    SELECT
            $$,
            replace(
                replace(_some_text, 't.', 'f.'),
                '"import_metadata"',
                'f."import_metadata"'
            )
        );
    END IF;

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
            -- comma is important because some fields exists before
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
            END AS geom
        $$;
        sql_text = sql_text || format(sql_template,
            _geometry_columns_record.srid
        );

    ELSIF _geometry_source = 'wkt' THEN
        sql_template = $$
            -- comma is important because some fields exists before
            ,
            CASE
                WHEN
                    s.wkt IS NOT NULL
                    AND lizmap_import_module.import_csv_is_given_type(s.wkt, 'wkt')
                THEN
                    ST_Transform(
                        ST_SetSRID(
                            ST_GeomFromText(s.wkt::text),
                            %1$s
                        ),
                        %1$s
                    )
                ELSE NULL
            END AS geom
        $$;
        sql_text = sql_text || format(sql_template,
            _geometry_columns_record.srid
        );
    END IF;

    -- import metadata
    sql_text = sql_text || format(
        $$
            -- comma is important because some fields exists before
            ,
            json_build_object(
                'import_login', '%1$s',
                'import_temp_table', '%2$s',
                'import_time', now()::timestamp(0),
                'action', 'I'
        ) AS import_metadata
        $$,
        _import_login,
        _temporary_table
    );

    -- Get data from source
    sql_text = sql_text || format(
        $$
            FROM "%1$s"."%2$s" AS s
        $$,
        _target_schema,
        _temporary_table
    );

    -- Build the SQL WHERE clause to update or upsert only when needed
    IF _import_type IN ('update', 'upsert') THEN
        _update_when_needed = '
            AND (
        ';
        _comma = '';
        FOR _var_csv_field IN
            SELECT field FROM unnest(_target_fields) AS field
        LOOP
            IF _import_type = 'update' THEN
                sql_template = ' %1$s t."%2$s" != f."%2$s"';
            ELSE
                sql_template = ' %1$s t."%2$s" != EXCLUDED."%2$s"';
            END IF;
            _update_when_needed = _update_when_needed || format(sql_template,
                _comma,
                _var_csv_field
            );
            _comma = ' OR ';
        END LOOP;

        IF _geometry_source IN ('lonlat', 'wkt') THEN
            _update_when_needed = _update_when_needed || format(
                CASE
                    WHEN _import_type = 'update'
                    THEN ' OR t."%1$s" != f."%1$s"'
                    ELSE ' OR t."%1$s" != EXCLUDED."%1$s"'
                END,
                quote_ident(_geometry_columns_record.f_geometry_column)
            );
        END IF;
        _update_when_needed = _update_when_needed || '
            )
        ';

        RAISE NOTICE 'update_when_needed = %', _update_when_needed;
    END IF;

    -- Adapt SQL depending on the import type
    -- UPDATE
    IF _import_type = 'update' THEN
        sql_text = sql_text || format(
            $$
                ) AS f
                WHERE True
                AND t."%1$s"::text = f."%1$s"::text
            $$,
            _unique_id_field
        );
        -- update only when needed
        sql_text = sql_text || _update_when_needed;

    END IF;

    -- INSERT
    -- Do not insert conflicted data
    IF _import_type = 'insert' THEN
        sql_text = sql_text || format(
            $$
                ON CONFLICT ON CONSTRAINT "%1$s_%2$s_import_csv_unique"
                DO NOTHING
            $$,
            _target_schema,
            _target_table
        );
    END IF;

    -- UPSERT : If the data is already there, update
    IF _import_type = 'upsert' THEN
        sql_text = sql_text || format(
            $$
                ON CONFLICT ON CONSTRAINT "%1$s_%2$s_import_csv_unique"
                DO UPDATE
                SET
            $$,
            _target_schema,
            _target_table
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
        IF _geometry_source IN ('lonlat', 'wkt') THEN
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

        -- UPSERT only when needed
        sql_text = sql_text || $$
            WHERE True
        $$ || _update_when_needed;
    END IF;

    -- return the primary keys inserted or modified
    sql_text = sql_text || format(
        $$
            RETURNING t."%1$s"
        $$,
        _target_table_pkeys->0->>'field_name'
    );

    RAISE NOTICE '%', sql_text;

    -- Import data
    RETURN QUERY EXECUTE sql_text;

END
$BODY$;

COMMENT ON FUNCTION lizmap_import_module.import_csv_data_to_target_table(text, text, text, text[], text, text, text, text)
    IS 'Import the data from the temporary table into the target table';

-- Delete the imported data, for example if errors have been encountered
DROP FUNCTION IF EXISTS lizmap_import_module.import_csv_delete_imported_data(text, text, text);
CREATE FUNCTION lizmap_import_module.import_csv_delete_imported_data(
    _temporary_table text,
    _target_schema text,
    _target_table text
)
RETURNS BOOLEAN AS
$BODY$
DECLARE
    sql_template text;
    sql_text text;
BEGIN

    sql_template = $$
        DELETE FROM "%1$s"."%2$s"
        WHERE import_metadata->>'import_temp_table' = _temporary_table::text;
    $$
    ;
    sql_text = format(sql_template,
        _target_schema,
        _target_table
    );

    RETURN True;

END
$BODY$
LANGUAGE plpgsql VOLATILE
COST 100
;

COMMENT ON FUNCTION lizmap_import_module.import_csv_delete_imported_data(text, text, text)
IS 'Delete imported data. It is used by the client script when errors have been encountered during the import.'
;
