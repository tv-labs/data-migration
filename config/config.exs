import Config

if config_env() == :test do
  config :logger, level: :info

  config :data_migration, Test.Endpoint,
    url: [host: "localhost", port: 4000],
    secret_key_base: "Hu4qQN3iKzTV4fJxhorPQlA/osH9fAMtbtjVS58PFgfw3ja5Z18Q/WSNR9wP4OfW",
    live_view: [signing_salt: "hMegieSe"],
    render_errors: [view: Test.ErrorView],
    check_origin: false,
    pubsub_server: Test.PubSub

  config :data_migration, ecto_repos: [Test.PGRepo, Test.TDSRepo, Test.SQLiteRepo, Test.MyXQLRepo]

  pool_size = max(10, System.schedulers_online() * 2)
  database = "data_migration_test"

  config :data_migration, Test.PGRepo,
    database: database,
    hostname: "localhost",
    port: 15435,
    username: "postgres",
    password: "postgres",
    pool_size: pool_size,
    pool: Ecto.Adapters.SQL.Sandbox

  config :data_migration, Test.TDSRepo,
    database: database,
    hostname: "localhost",
    port: 11433,
    username: "sa",
    password: "StrongPassword!",
    pool_size: pool_size,
    pool: Ecto.Adapters.SQL.Sandbox

  config :data_migration, Test.MyXQLRepo,
    hostname: "localhost",
    database: database,
    database: database,
    username: "mysql",
    password: "mysql",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: pool_size,
    port: 13306

  config :data_migration, Test.SQLiteRepo,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: pool_size,
    migration_lock: false,
    database: "test.db"
end
