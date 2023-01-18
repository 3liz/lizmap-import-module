# Run docker compose

Steps:

- Launch Lizmap with docker compose

```bash
# Clean previous versions (optional)
make clean

# Run the different services
make run

# Add the needed data
# Lizmap ACL
make import-lizmap-acl
# PostgreSQL test data
```

- Open your browser at http://localhost:9085

## Access to the dockerized PostgreSQL instance

You can access the docker PostgreSQL test database `lizmap` from your host by configuring a
[service file](https://docs.qgis.org/latest/en/docs/user_manual/managing_data_source/opening_data.html#postgresql-service-connection-file).
The service file can be stored in your user home `~/.pg_service.conf` and should contain this section

```ini
[lizmap-import]
dbname=lizmap
host=localhost
port=9087
user=lizmap
password=lizmap1234!
```

Then you can use any PostgreSQL client (psql, QGIS, PgAdmin, DBeaver) and use the `service`
instead of the other credentials (host, port, database name, user and password).

```bash
psql service=lizmap-import
```

## Access to the lizmap container

If you want to enter into the lizmap container to execute some commands,
execute `make shell`.

## Add the test data

```bash
make import-data
```

# Export the test data after some modification

You can edit the data of the PostgreSQL database, and then update the content of
the test data file `test_data.sql` with:

```bash
make export-data
```
