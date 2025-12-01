defmodule DataMigration.LoggerTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias DataMigration.Logger, as: DMLogger

  @pubsub_server Test.PubSub
  @topic "test-migration-logs"

  defmodule TestDataMigration do
    @moduledoc false
    require Logger

    def foo, do: Logger.warning("foo")

    defmodule Namespace.SomeModule do
      @moduledoc false
      require Logger

      def foo, do: Logger.error("test")
    end
  end

  @listen_to [TestDataMigration.Namespace, {TestDataMigration, :foo, 0}]

  describe "add/4" do
    test "successfully adds logger handler" do
      id = "test_migration_#{System.unique_integer()}"

      assert :ok = DMLogger.add(id, @pubsub_server, @topic, @listen_to)

      # Clean up
      DMLogger.remove(id)
    end

    test "returns ok if handler already exists" do
      id = "test_migration_#{System.unique_integer()}"
      assert :ok = DMLogger.add(id, @pubsub_server, @topic, @listen_to)
      assert :ok = DMLogger.add(id, @pubsub_server, @topic, @listen_to)

      # Clean up
      DMLogger.remove(id)
    end
  end

  describe "remove/1" do
    test "removes logger handler" do
      id = "test_migration_#{System.unique_integer()}"
      DMLogger.add(id, @pubsub_server, @topic, @listen_to)
      assert :ok = DMLogger.remove(id)
    end

    test "handles removing non-existent handler" do
      id = "non_existent_#{System.unique_integer()}"
      assert {:error, {:not_found, _}} = DMLogger.remove(id)
    end
  end

  describe "adding_handler/1" do
    test "validates pubsub_server is present" do
      config = []
      assert {:error, "requires a pubsub_server"} = DMLogger.adding_handler(config)
    end

    test "accepts valid config with pubsub_server" do
      config = [pubsub_server: @pubsub_server]
      assert {:ok, ^config} = DMLogger.adding_handler(config)
    end
  end

  describe "changing_config/3" do
    test "updates config with new values" do
      old_config = [pubsub_server: @pubsub_server, topic: "old_topic"]
      new_config = [topic: "new_topic"]

      assert {:ok, updated_config} = DMLogger.changing_config(:update, old_config, new_config)
      assert updated_config[:pubsub_server] == @pubsub_server
      assert updated_config[:topic] == "new_topic"
    end

    test "sets entire config" do
      old_config = [pubsub_server: @pubsub_server, topic: "old_topic"]
      new_config = [pubsub_server: @pubsub_server, topic: "new_topic"]

      assert {:ok, ^new_config} = DMLogger.changing_config(:set, old_config, new_config)
    end

    test "validates pubsub_server in new config" do
      old_config = [pubsub_server: @pubsub_server]
      new_config = [topic: "new_topic"]

      assert {:error, "requires a pubsub_server"} =
               DMLogger.changing_config(:set, old_config, new_config)
    end
  end

  describe "filter_config/1" do
    test "returns config unchanged" do
      config = [pubsub_server: @pubsub_server, topic: @topic]
      assert DMLogger.filter_config(config) == config
    end
  end

  describe "log/2" do
    setup do
      Phoenix.PubSub.subscribe(@pubsub_server, @topic)
      id = "test_migration_#{System.unique_integer()}"
      on_exit(fn -> DMLogger.remove(id) end)

      %{id: id}
    end

    test "listens to module logs within mfa", %{id: id} do
      assert :ok = DMLogger.add(id, @pubsub_server, @topic, @listen_to)

      capture_log(fn ->
        TestDataMigration.foo()
      end)

      assert_receive {DataMigration.Logger, {:logger, :warning, log}}
      assert "warning" in log
      assert "foo" in log
    end

    test "listens to module logs within namespace", %{id: id} do
      assert :ok = DMLogger.add(id, @pubsub_server, @topic, @listen_to)

      capture_log(fn ->
        TestDataMigration.Namespace.SomeModule.foo()
      end)

      assert_receive {DataMigration.Logger, {:logger, :error, log}}
      assert "error" in log
      assert "test" in log
    end
  end

  describe "removing_handler/1" do
    test "returns ok" do
      assert :ok = DMLogger.removing_handler(%{})
    end
  end

  describe ":gen_event callbacks" do
    test "init/1 configures logger format and metadata" do
      config = %{pubsub: @pubsub_server, topic: @topic, listen_to: []}

      assert {:ok, {_format, _metadata, ^config}} = DMLogger.init(config)
    end

    test "handle_call/2 returns ok" do
      state = {nil, [], %{}}
      assert {:ok, :ok, ^state} = DMLogger.handle_call({:configure, []}, state)
    end

    test "handle_event/2 ignores events from other nodes" do
      remote_gl =
        spawn_link(fn ->
          receive do
            :ok -> :ok
          end
        end)

      event = {:info, remote_gl, {Logger, "message", {{2023, 1, 1}, {0, 0, 0, 0}}, []}}
      state = {nil, [], %{listen_to: []}}

      assert {:ok, ^state} = DMLogger.handle_event(event, state)
    end

    test "handle_info/2 returns ok" do
      state = {nil, [], %{}}
      assert {:ok, ^state} = DMLogger.handle_info(:some_message, state)
    end
  end
end
