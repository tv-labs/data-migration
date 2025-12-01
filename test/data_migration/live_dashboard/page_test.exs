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
end
