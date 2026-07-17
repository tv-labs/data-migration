defmodule DataMigration.Test.Fixtures.Noop do
  @moduledoc false
  use Ecto.Migration

  def up, do: :ok
  def down, do: :ok
end
