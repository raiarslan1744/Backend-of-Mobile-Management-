# Database-safe API startup

The existing production command, `dart run bin/server.dart`, connects using
`DATABASE_URL` and starts the API against the existing database. It does not run
schema initialization or super-admin seeding. No Render environment, Docker or
start-command change is required, and no environment flag enables bootstrap.

Startup does not create/alter/drop tables or constraints, create indexes, seed
accounts, update super-admin timestamps or replace stored credentials. Existing
login and sync request handling is unchanged: normal authenticated API operations
can still write the database. Missing schema/accounts are not silently repaired.

## Explicit setup for an authorized database

For controlled local setup only, configure `DATABASE_URL`,
`SUPER_ADMIN_USERNAME` and `SUPER_ADMIN_PASSWORD` for the intended local database,
then explicitly run:

```text
dart run bin/bootstrap.dart --initialize-database
```

This command retains the existing schema initialization and super-admin upsert
behavior, including its existing limitations. It mutates the target database and
does not start the API. Running it without the exact argument exits before any
database connection. Never run it against production without separate approval.

## Validation

The startup integration test only accepts the dedicated isolated database at
`127.0.0.1:55439/ak_unification_test`. It launches the real default server entry
point with a local read-only database role, checks both health routes and compares
schema/data snapshots before and after. A separate check restarts with deliberately
different bootstrap credential values and verifies that the original persisted
super-admin credentials still authenticate, while the replacement values do not.

Initialize that local fixture explicitly before running the complete backend test
suite with `dart test --concurrency=1`; snapshot checks must not overlap other
fixture writes. Do not point integration tests at a production database.
