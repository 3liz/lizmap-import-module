# Import SQL data for test purpose
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

# Delete the previous demo data
echo "=== Drop the existing demo schema and data"
psql service=lizmap-import -c "DROP SCHEMA IF EXISTS demo CASCADE;"

# Import data
echo "=== Add the demo schema with test data"
psql service=lizmap-import -f "$SCRIPT_DIR"/test_data.sql
