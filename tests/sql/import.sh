# Import SQL data for test purpose
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Add lizmap_import_module schema, tables and functions
echo "=== Add the lizmap_import_module schema, tables and functions"
psql service=lizmap-import -f "$SCRIPT_DIR"/../../import/install/sql/import.sql

# Delete the previous demo data
echo "=== Drop the existing demo schema and data"
psql service=lizmap-import -c "DROP SCHEMA IF EXISTS demo CASCADE;"

# Import data
echo "=== Add the demo schema with test data"
psql service=lizmap-import -f "$SCRIPT_DIR"/test_data.sql

# Import CSV field rules
echo "=== Add the configuration data (destination tables & field rules)"
psql service=lizmap-import -f "$SCRIPT_DIR"/csv_import_rules.sql
