defmodule DataMigration.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use DataMigration.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate
  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Phoenix.ConnTest, except: [build_conn: 0]
      import DataMigration.ConnCase

      # Import conveniences for testing with connections
      import Plug.Conn
    end
  end

  def build_conn do
    %{
      Phoenix.ConnTest.build_conn()
      | host: Application.get_env(:sauron, Test.Endpoint)[:url][:host]
    }
  end

  setup tags do
    test_repo = Application.get_env(:data_migration, :test_repo)
    route = Application.get_env(:data_migration, :mounted_at)
    _pid = Sandbox.start_owner!(test_repo, shared: not tags[:async])
    conn = Phoenix.ConnTest.init_test_session(build_conn(), %{})
    locations = %{test_repo => [route]}

    {:ok, locations: locations, route: "/dashboard/#{route}", repo: test_repo, conn: conn}
  end
end
