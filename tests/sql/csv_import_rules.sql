-- Remove existing rules
TRUNCATE lizmap_import_module.import_csv_destination_tables RESTART IDENTITY CASCADE;
TRUNCATE lizmap_import_module.import_csv_field_rules RESTART IDENTITY CASCADE;

-- Add destination table
INSERT INTO lizmap_import_module.import_csv_destination_tables (
        table_schema, table_name,
        lizmap_repository, lizmap_project,
        target_fields, geometry_source,
        unique_id_field, duplicate_check_fields
)
VALUES (
    'demo', 'trees',
    'tests', 'import',
    ARRAY['height', 'genus', 'leaf_type', 'tree_code'], 'lonlat',
    'id_csv', ARRAY['genus', 'tree_code']
)
;

-- Add rules for this table
INSERT INTO lizmap_import_module.import_csv_field_rules
(target_table_schema, target_table_name, criteria_type, code, label, description, condition)
VALUES
('demo', 'trees', 'not_null', 'genus_not_null', 'The field genus cannot be empty', NULL, $$genus IS NOT NULL$$),
('demo', 'trees', 'not_null', 'leaf_type_not_null', 'The field leaf_type cannot be empty', NULL, $$leaf_type IS NOT NULL$$),
('demo', 'trees', 'format', 'height_format', 'The field height must be a real number', NULL, $$lizmap_import_module.import_csv_is_given_type(height, 'integer')$$),
('demo', 'trees', 'format', 'wkt_format', 'The field "wkt" must be a valid WKT string', NULL, $$lizmap_import_module.import_csv_is_given_type(wkt, 'wkt')$$),
('demo', 'trees', 'valid', 'height_valid', 'The height value must be between 1.0 and 30.0', NULL, $$height BETWEEN 1.0 AND 30.0$$),
('demo', 'trees', 'valid', 'genus_valid', 'The genus must be Platanus or Cupressus', NULL, $$genus IN ('Cupressus', 'Platanus')$$)
;
