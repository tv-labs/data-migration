defmodule Test.ErrorView do
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

defmodule Test.Router do
  use Phoenix.Router
  import Phoenix.LiveDashboard.Router

  @options [listen_for_logs: [Test.DataMigrations]]

  pipeline :browser do
    plug(:fetch_session)
  end

  scope "/", Foo, as: :this_wont_be_used do
    pipe_through([:browser])

    live_dashboard("/dashboard",
      allow_destructive_actions: true,
      # Provide the page with Repo and migration folders config
      additional_pages: [
        data_migrations_pg:
          {DataMigration.LiveDashboard.Page,
           {Test.PubSub, %{Test.PGRepo => ["data_migrations_pg"]}, @options}},
        data_migrations_myxql:
          {DataMigration.LiveDashboard.Page,
           {Test.PubSub, %{Test.MyXQLRepo => ["data_migrations_myxql"]}, @options}},
        data_migrations_tds:
          {DataMigration.LiveDashboard.Page,
           {Test.PubSub, %{Test.TDSRepo => ["data_migrations_tds"]}, @options}},
        data_migrations_sqlite:
          {DataMigration.LiveDashboard.Page,
           {Test.PubSub, %{Test.SQLiteRepo => ["data_migrations_sqlite"]}, @options}}
      ]
    )
  end
end

defmodule Test.Endpoint do
  use Phoenix.Endpoint, otp_app: :data_migration

  plug(Plug.Session,
    store: :cookie,
    key: "_live_view_key",
    signing_salt: "/VEDsdfsffMnp5"
  )

  plug(Test.Router)
end
