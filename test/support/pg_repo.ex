defmodule Test.PGRepo do
  use Ecto.Repo, otp_app: :data_migration, adapter: Ecto.Adapters.Postgres
end
