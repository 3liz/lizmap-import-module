-- Change constraint on  geometry source
ALTER TABLE lizmap_import_module.import_csv_destination_tables
DROP CONSTRAINT IF EXISTS import_csv_destination_tables_geometry_source_valid
;
ALTER TABLE lizmap_import_module.import_csv_destination_tables
ADD CONSTRAINT import_csv_destination_tables_geometry_source_valid
CHECK (geometry_source IN ('none', 'lonlat', 'wkt'));

-- Add column to set the type of import
ALTER TABLE lizmap_import_module.import_csv_destination_tables
ADD COLUMN import_type text NOT NULL DEFAULT 'insert'
;
ALTER TABLE lizmap_import_module.import_csv_destination_tables
ADD CONSTRAINT import_csv_destination_tables_import_type_valid
CHECK (import_type IN ('insert', 'update', 'upsert'))
;
COMMENT ON COLUMN lizmap_import_module.import_csv_destination_tables.import_type
IS 'Defines the type of import allowed :
* insert = only new data,
* update = only update based on given unique_id_field
* upsert = insert new data & update data on conflict based on duplicate_check_fields'
;


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


-- Import the data from the temporary table to the target table
DROP FUNCTION IF EXISTS lizmap_import_module.import_csv_data_to_target_table(text, text, text, text[], text, text);
DROP FUNCTION IF EXISTS lizmap_import_module.import_csv_data_to_target_table(text, text, text, text[], text, text, text[]);
DROP FUNCTION IF EXISTS lizmap_import_module.import_csv_data_to_target_table(text, text, text, text[], text, text, text, text);
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

    -- Adapt SQL depending on the import type
    IF _import_type = 'update' THEN
        sql_text = sql_text || format(
            $$
                ) AS f
                WHERE True
                AND t."%1$s" = f."%1$s"
            $$,
            _unique_id_field
        );

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
        sql_text = sql_text || '
            WHERE True AND (
        ';
        _comma = '';
        FOR _var_csv_field IN
            SELECT field FROM unnest(_target_fields) AS field
        LOOP
            sql_template = ' %1$s t."%2$s" != EXCLUDED."%2$s"';
            sql_text = sql_text || format(sql_template,
                _comma,
                _var_csv_field
            );
            _comma = ' OR ';
        END LOOP;

        IF _geometry_source IN ('lonlat', 'wkt') THEN
            sql_text = sql_text || format(
                ' OR t."%1$s" != EXCLUDED."%1$s"',
                quote_ident(_geometry_columns_record.f_geometry_column)
            );
        END IF;
        sql_text = sql_text || '
            )
        ';
    END IF;

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

COMMENT ON FUNCTION lizmap_import_module.import_csv_data_to_target_table(text, text, text, text[], text, text, text, text)
    IS 'Import the data from the temporary table into the target table';
