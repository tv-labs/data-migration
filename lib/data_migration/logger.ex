defmodule DataMigration.Logger do
  @moduledoc """
  A logger backend that will capture logs from Ecto migrations.
  This is destined for the Phoenix LiveView Dashboard
  data migration page for monitoring results when the data migration is ran.
  """

  # This is a copy of https://github.com/phoenixframework/phoenix_live_dashboard/blob/fab5e4f5c1c5d7aa5a3960878e2aa5e06f6753d9/lib/phoenix/live_dashboard/logger_pubsub_backend.ex
  # but modified to capture `Ecto.Migration.Runner` logs

  @behaviour :gen_event
  @behaviour :logger_handler

  # API

  # Ignored because the `:logger_handler.config` type has a
  # defined set of keys in config.
  @dialyzer {:nowarn_function, add: 4}
  def add(migration_id, pubsub_server, topic, listen_to_modules) do
    handler_config = handler_config(pubsub_server, topic, listen_to_modules)
    handler_id = Module.concat(__MODULE__, migration_id)

    case :logger.add_handler(handler_id, __MODULE__, handler_config) do
      :ok -> :ok
      {:error, {:already_exist, _}} -> :ok
      error -> error
    end
  end

  @listen_to [{Ecto.Adapters.SQL}, {Ecto.Migration.Runner}, {Ecto.Migrator}]
  defp handler_config(pubsub_server, topic, listen_to_modules) do
    listen_to =
      listen_to_modules
      |> List.wrap()
      |> Enum.map(fn
        mfa when is_tuple(mfa) -> mfa
        module_namespace when is_atom(module_namespace) -> Module.split(module_namespace)
      end)

    %{
      pubsub_server: pubsub_server,
      topic: topic,
      listen_to: listen_to ++ @listen_to,
      formatter: Logger.default_formatter(colors: [enabled: false])
    }
  end

  def remove(id) do
    :logger.remove_handler(Module.concat(__MODULE__, id))
  end

  # :logger_handler callbacks =========

  @impl :logger_handler
  def adding_handler(config) do
    case config[:pubsub_server] do
      nil -> {:error, "requires a pubsub_server"}
      _ -> {:ok, config}
    end
  end

  @impl :logger_handler
  def changing_config(:update, old_config, new_config) do
    changing_config(:set, old_config, Keyword.merge(old_config, new_config))
  end

  def changing_config(:set, _old_config, new_config) do
    case new_config[:pubsub_server] do
      nil -> {:error, "requires a pubsub_server"}
      _ -> {:ok, new_config}
    end
  end

  @impl :logger_handler
  def filter_config(config), do: config

  @impl :logger_handler
  def log(%{meta: metadata, level: level} = event, config) do
    if capture?(metadata[:mfa], config.listen_to) do
      %{formatter: {formatter_mod, formatter_config}} = config
      chardata = formatter_mod.format(event, formatter_config)

      Phoenix.PubSub.broadcast(
        config.pubsub_server,
        config.topic,
        {__MODULE__, {:logger, level, chardata}}
      )
    end
  end

  defp capture?({m, f, a}, modules) do
    Enum.any?(modules, fn
      namespace when is_list(namespace) ->
        namespace == m |> Module.split() |> Enum.take(length(namespace))

      {^m} ->
        true

      {^m, ^f} ->
        true

      {^m, ^f, ^a} ->
        true

      _ ->
        false
    end)
  end

  defp capture?(_, _), do: false

  @impl :logger_handler
  def removing_handler(_config), do: :ok

  # :gen_event handlers =========

  @impl :gen_event
  def init(config) do
    logger_config =
      Application.get_env(:logger, :default_formatter) ||
        Application.get_env(:logger, :console) || []

    format = Logger.Formatter.compile(Keyword.get(logger_config, :format))
    metadata = logger_config |> Keyword.get(:metadata, []) |> configure_metadata()
    {:ok, {format, metadata, config}}
  end

  @impl :gen_event
  def handle_call({:configure, _options}, state) do
    {:ok, :ok, state}
  end

  @impl :gen_event
  def handle_event({level, gl, {Logger, msg, ts, metadata}}, {format, keys, config} = state)
      when node(gl) == node() do
    if capture?(metadata[:mfa], config.listen_to) do
      metadata = take_metadata(metadata, keys)
      formatted = Logger.Formatter.format(format, level, msg, ts, metadata)

      Phoenix.PubSub.broadcast(
        config.pubsub,
        config.topic,
        {__MODULE__, {:logger, level, formatted}}
      )
    end

    {:ok, state}
  end

  def handle_event(_, state) do
    {:ok, state}
  end

  @impl true
  def handle_info(_, state) do
    {:ok, state}
  end

  defp configure_metadata(:all), do: :all
  defp configure_metadata(metadata), do: Enum.reverse(metadata)

  defp take_metadata(metadata, :all) do
    metadata
  end

  defp take_metadata(metadata, keys) do
    Enum.reduce(keys, [], fn key, acc ->
      case Keyword.fetch(metadata, key) do
        {:ok, val} -> [{key, val} | acc]
        :error -> acc
      end
    end)
  end
end
