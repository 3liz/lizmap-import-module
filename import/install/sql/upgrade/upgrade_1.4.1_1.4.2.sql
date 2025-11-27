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


-- Add fields
ALTER TABLE lizmap_import_module.import_csv_field_rules ADD COLUMN IF NOT EXISTS lizmap_repository text;
ALTER TABLE lizmap_import_module.import_csv_field_rules ADD COLUMN IF NOT EXISTS lizmap_project text;


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
