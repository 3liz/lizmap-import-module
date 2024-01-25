## Run Lizmap stack with docker compose

Steps:

* Launch Lizmap with docker compose

```bash
# Clean previous versions (optional)
make clean

# Run the different services
make run
```

* Open your browser at `http://localhost:9085`

For more information, refer to the [docker compose documentation](https://docs.docker.com/compose/)


## Add the test data

You can add some test data in your docker test PostgreSQL database by running the SQL files `tests/sql/test_schema.sql` and `tests/sql/test_data.sql`.
**You need to import these data before installing the module.**

```bash
make import-test-data
```

If you have modified your test data suite (for example after upgrading to a new version)
please run :

```bash
make export-test-data
```

Then add the modified file `tests/sql/test_data.sql` to your pull request.


## Install the module

* Install the module with:

```bash
make install-module
```

* Add the needed Lizmap rights:


```bash
make import-lizmap-acl
```

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
