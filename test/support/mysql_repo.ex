defmodule Test.MyXQLRepo do
  use Ecto.Repo, otp_app: :data_migration, adapter: Ecto.Adapters.MyXQL
end
