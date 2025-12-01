defmodule Test.SQLiteRepo do
  use Ecto.Repo, otp_app: :data_migration, adapter: Ecto.Adapters.SQLite3
end
