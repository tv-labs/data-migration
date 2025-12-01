if System.get_env("ECTO_ADAPTER") == "pg" do
  Application.put_env(:data_migration, :test_repo, Test.PGRepo)
  Application.put_env(:data_migration, :mounted_at, "data_migrations_pg")
  _ = Ecto.Adapters.Postgres.storage_up(Test.PGRepo.config())
end

if System.get_env("ECTO_ADAPTER") == "myxql" do
  Application.put_env(:data_migration, :test_repo, Test.MyXQLRepo)
  Application.put_env(:data_migration, :mounted_at, "data_migrations_myxql")
  _ = Ecto.Adapters.MyXQL.storage_up(Test.MyXQLRepo.config())
end

if System.get_env("ECTO_ADAPTER") == "tds" do
  Application.put_env(:data_migration, :test_repo, Test.TDSRepo)
  Application.put_env(:data_migration, :mounted_at, "data_migrations_tds")
  _ = Ecto.Adapters.Tds.storage_up(Test.TDSRepo.config())
end

if System.get_env("ECTO_ADAPTER") in ["sqlite", nil] do
  Application.put_env(:data_migration, :test_repo, Test.SQLiteRepo)
  Application.put_env(:data_migration, :mounted_at, "data_migrations_sqlite")
  _ = Ecto.Adapters.SQLite3.storage_up(Test.SQLiteRepo.config())
end

# ==== Setup

Mix.Shell.IO.info(
  "Database containers must be running, otherwise you will run into an issue starting."
)

repo = Application.get_env(:data_migration, :test_repo)

Supervisor.start_link(
  List.wrap(repo) ++
    [
      {Ecto.Migrator, repos: [repo], skip: repo == Test.SQLiteRepo},
      {Phoenix.PubSub, name: Test.PubSub, adapter: Phoenix.PubSub.PG2},
      Test.Endpoint
    ],
  strategy: :one_for_one
)

Ecto.Migration.SchemaMigration.ensure_schema_migrations_table!(repo, repo.config(), [])

ExUnit.start()
