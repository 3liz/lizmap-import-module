# Import SQL data for test purpose
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Delete data
psql service=lizmap-import -c "DROP SCHEMA IF EXISTS demo CASCADE;"

# Import data
psql service=lizmap-import -f "$SCRIPT_DIR"/test_data.sql

# Import CSV rules
psql service=lizmap-import -f "$SCRIPT_DIR"/csv_import_rules.sql
