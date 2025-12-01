# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Elixir library that provides a Phoenix LiveDashboard page for managing Ecto data migrations. It allows viewing, running, and monitoring data migrations with real-time log streaming through Phoenix PubSub.

## Multi-Database Testing Architecture

The project supports multiple database adapters (PostgreSQL, MySQL, MSSQL, SQLite) and uses environment variables to switch between them during testing:

- **ECTO_ADAPTER environment variable** controls which database adapter tests run against
  - `pg` - PostgreSQL (Test.PGRepo)
  - `myxql` - MySQL (Test.MyXQLRepo)
  - `tds` - SQL Server/MSSQL (Test.TDSRepo)
  - `sqlite` or unset - SQLite (Test.SQLiteRepo, default)

- **Database connection details** for local testing (via docker-compose):
  - PostgreSQL: localhost:15435
  - MySQL: localhost:13306
  - SQL Server: localhost:11433

## Common Commands

### Testing

Run tests for a specific database adapter:
```bash
ECTO_ADAPTER=sqlite mix test
ECTO_ADAPTER=pg mix test
ECTO_ADAPTER=myxql mix test
ECTO_ADAPTER=tds mix test
```

Run tests for all adapters sequentially:
```bash
mix test.all
```

Run a single test file:
```bash
ECTO_ADAPTER=pg mix test test/data_migration/live_dashboard/page_test.exs
```

### Development

Start database containers (required before running tests):
```bash
docker-compose up -d
```

Stop database containers:
```bash
docker-compose down
```

Format code:
```bash
mix format
```

Compile with warnings as errors:
```bash
mix compile --force --warnings-as-errors
```

Start the development dashboard (uses Tidewave at port 4011):
```bash
mix tidewave
```

### Dependencies

Get dependencies:
```bash
mix deps.get
```

## Architecture

### Core Components

1. **DataMigration.LiveDashboard.Page** (`lib/data_migration/live_dashboard/page.ex`)
   - Phoenix LiveView page that integrates with LiveDashboard
   - Lists all data migrations from configured Ecto repos and folders
   - Provides UI to run migrations up/down with confirmation
   - Streams logs in real-time via PubSub as migrations execute
   - Uses `Ecto.Migrator` for migration discovery and execution
   - Caches migration list in `:persistent_term` for performance
   - In dev mode, automatically recompiles migrations on each page load

2. **DataMigration.Logger** (`lib/data_migration/logger.ex`)
   - Custom logger backend that captures Ecto migration logs
   - Implements both `:gen_event` (legacy) and `:logger_handler` (OTP 21+) behaviors
   - Filters logs by MFA (module/function/arity) patterns
   - Broadcasts captured logs to Phoenix PubSub topic
   - Automatically captures logs from: `Ecto.Adapters.SQL`, `Ecto.Migration.Runner`, `Ecto.Migrator`

### Configuration Pattern

The LiveDashboard page is configured in the Phoenix router with a 3-tuple:
```elixir
{PubSubServer, %{Repo => [migration_folders]}, options}
```

Example:
```elixir
{MyApp.PubSub, %{MyApp.Repo => ["data_migrations"]}, [topic: "custom-topic"]}
```

### Migration Discovery

- Uses `Ecto.Migrator.migrations/3` to get migration status
- Compiles migration files dynamically with `Code.require_file/2`
- Extracts metadata: id, name, file path, status (:up or :down)
- Matches migration files by glob pattern: `*.exs` in configured folders

## Test Structure

- **test/support/** contains test repos for each database adapter
- **test/support/conn_case.ex** provides test helpers
- **test/support/endpoint.ex** is a minimal Phoenix endpoint for testing
- Tests are adapter-specific and selected at runtime via environment variable
- CI runs the full test suite against all adapters sequentially

## Important Development Notes

- When adding Ecto-related features, ensure compatibility with all four adapters (pg, myxql, tds, sqlite)
- The logger captures logs based on MFA patterns - be mindful of what gets captured
- Migration status is queried on each page load but cached in persistent_term
- The page requires `allow_destructive_actions: true` in LiveDashboard config to enable migration execution
- ANSI color codes are stripped from logs before displaying in the UI
