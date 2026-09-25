# Changelog

## unreleased

- Add `DataMigration.pending/2`, which lists the data migrations that have not
  run, oldest first.
- Add `DataMigration.run/4`, which runs one data migration by version. It runs
  nothing and returns an error for a version no file has, or for a one-shot data
  migration that has run.
- Add `use DataMigration, repeatable: true` to mark a data migration that can
  run again. A data migration is one-shot unless it says so.
- Tests run the sandbox in manual mode, so a migration a test runs no longer
  leaves its row in the test database.

## 0.1.2 (2026-08-05)

- Fixup Elixir 1.20 type warning

## 0.1.1 (2026-07-16)

- Fix concurrent LiveView accumulating duplicate migrations over time.
- Fix concurrent processes listing migrations and one getting none back

## 0.1.0 (2025-12-03)

- Initial release
