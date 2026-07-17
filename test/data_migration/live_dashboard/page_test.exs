defmodule DataMigration.LiveDashboard.PageTest do
  use DataMigration.ConnCase, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  alias DataMigration.LiveDashboard.Page

  @endpoint Test.Endpoint
  @pubsub_server Test.PubSub
  @topic "data-migration-logs"

  describe "init/1" do
    test "initializes with pubsub and locations", %{locations: locations} do
      assert {:ok, opts, []} = Page.init({@pubsub_server, locations})

      assert opts == %{
               topic: @topic,
               listen_to: [],
               pubsub: @pubsub_server,
               locations: locations
             }
    end

    test "initializes with custom topic", %{locations: locations} do
      custom_topic = "custom-topic"

      assert {:ok, opts, []} = Page.init({@pubsub_server, locations, topic: custom_topic})

      assert opts == %{
               topic: custom_topic,
               pubsub: @pubsub_server,
               listen_to: [],
               locations: locations
             }
    end

    test "initializes with modules to listen to", %{locations: locations} do
      assert {:ok, opts, []} =
               Page.init({@pubsub_server, locations, listen_for_logs: [FooBar.Baz]})

      assert opts == %{
               listen_to: [FooBar.Baz],
               topic: @topic,
               pubsub: @pubsub_server,
               locations: locations
             }
    end
  end

  describe "Page" do
    test "mounts successfully with default assigns", %{route: route, conn: conn} do
      assert route
      assert {:ok, _view, _html} = live(conn, route)
    end
  end

  describe "list_data_migrations/1 (regression)" do
    setup do
      :persistent_term.erase(:data_migration_list)
      :ok
    end

    test "a fresh mount reflects the true status after a migration ran, with no duplicate rows",
         %{route: route, conn: conn, repo: repo} do
      # `folder` (unlike `route`) must match what the UI sends via
      # phx-value-folder: the path relative to the app dir, not the config key.
      config_folder = Application.get_env(:data_migration, :mounted_at)

      folder =
        repo
        |> Ecto.Migrator.migrations_path(config_folder)
        |> String.split(Application.app_dir(:data_migration) <> "/", parts: 2)
        |> List.last()

      repo_param = inspect(repo)

      {:ok, view, html} = live(conn, route)
      assert html =~ "down"

      html =
        render_click(view, "navigate", %{
          "id" => "99999999999999",
          "repo" => repo_param,
          "folder" => folder
        })

      assert html =~ "down"

      render_click(view, "are-you-sure-up", %{})

      html =
        render_click(view, "migrate-up", %{
          "id" => "99999999999999",
          "repo" => repo_param,
          "folder" => folder
        })

      assert html =~ "up"

      # Simulates a reload: re-enters list_data_migrations/1, which a
      # concurrent session (e.g. the "mounts successfully" test above,
      # same async run) could otherwise have clobbered with a stale entry.
      list_html = render_click(view, "navigate", %{"action" => "list"})

      # A stale cached duplicate would show up as a second phx-value-id.
      assert list_html
             |> String.split(~s(phx-value-id="99999999999999"))
             |> length() == 2

      show_html =
        render_click(view, "navigate", %{
          "id" => "99999999999999",
          "repo" => repo_param,
          "folder" => folder
        })

      assert show_html =~ ~s(data-status="up")
      refute show_html =~ ~s(data-status="down")
    end
  end
end
