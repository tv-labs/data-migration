defmodule DataMigration.LiveDashboard.Page do
  @moduledoc """
  The page to view data migrations.

  For example, in your Phoenix router:

    live_dashboard "/my/admin/dashboard",
      # must have `allow_destructive_actions: true` in order to run data migrations
      # otherwise it will be view-only to see the status
      allow_destructive_actions: true,
      # Provide the page with Repo and migration folders config
      additional_pages: [
        # so the route becomes "/my/admin/dashboard/data_migrations"
        data_migrations: {
          DataMigration.LiveDashboard.Page,
          {MyApp.PubSub, %{MyApp.Repo => ["data_migrations"]}, options}
          # These paths will be passed into `Ecto.Migrator.migrations_path(repo, path)`
          # `options` is optional; you may supply 2 item tuple instead to omit options
        }
      ]

  Options you may supply to the page:

  - `:topic` a different PubSub topic to listen to for capturing migration logs.
  - `:listen_for_logs` A list of MFAs (tuple of length 1, 2, or 3) for which the page to listen for logs.
      You can also supply a module namespace, eg, `MyApp.DataMigration` and any module under that namespace
      will have its logs listened to, eg `MyApp.DataMigration.FooBar`
  """

  use Phoenix.LiveDashboard.PageBuilder

  alias Phoenix.LiveDashboard.PageBuilder

  @topic "data-migration-logs"
  @doc "The default topic #{inspect(@topic)} that the page will listen for on the provided `pubsub_server` for logs"
  def topic, do: @topic

  @impl PageBuilder
  def menu_link(_session, _capabilities) do
    {:ok, "Data Migrations"}
  end

  @impl PageBuilder
  def init({pubsub, locations}), do: init({pubsub, locations, []})

  def init({pubsub, locations, opts}) do
    listen_to = opts[:listen_for_logs] || []
    topic = opts[:topic] || @topic
    {:ok, %{topic: topic, listen_to: listen_to, pubsub: pubsub, locations: locations}, []}
  end

  @impl PageBuilder
  def mount(_params, opts, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(opts.pubsub, opts.topic)
    end

    {:ok,
     socket
     |> assign(:data_migrations, [])
     |> assign(:data_migration, nil)
     |> assign(:opts, opts)
     |> assign(:are_you_sure_up, nil)
     |> assign(:are_you_sure_down, nil)
     |> assign(:logs_present, false)
     |> stream_configure(:logs, dom_id: fn _ -> "log-#{System.unique_integer([:monotonic])}" end)
     |> stream(:logs, [])}
  end

  @impl PageBuilder
  def handle_params(params, _uri, socket) do
    migrations = list_data_migrations(socket.assigns.opts.locations)

    migration =
      if params["action"] == "show" do
        find_migration(migrations, params["id"], params["folder"], params["repo"])
      end

    {:noreply,
     socket
     |> assign(:data_migrations, migrations)
     |> assign(:data_migration, migration)}
  end

  @impl PageBuilder
  def render(%{data_migration: nil} = assigns) do
    ~H"""
    <.event_logs logs_present={@logs_present} stream={@streams.logs} />
    <.live_table
      id="data-migration-table"
      default_sort_by={:id}
      limit={false}
      page={@page}
      title="Data Migrations"
      row_fetcher={&row_fetcher(@data_migrations, &1, &2)}
      row_attrs={&list_row_attrs/1}
      rows_name="data_migrations"
    >
      <:col field={:id} header="ID" sortable={:desc} />
      <:col field={:status} text_align="center" sortable={:asc} />
      <:col field={:name} sortable={:asc} />
    </.live_table>
    """
  end

  @impl PageBuilder
  def render(assigns) do
    ~H"""
    <.event_logs logs_present={@logs_present} stream={@streams.logs} />
    <.card_title title={@data_migration.name} />
    <div id={"data-migration-#{@data_migration.id}"} class="mb-4 mt-4 banner-card">
      <button
        style="border: 0; background: none; width: 2.5rem; height: 2.5rem"
        phx-value-action="list"
        phx-click="navigate"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.5"
          stroke="currentColor"
          class="size-6"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18"
          />
        </svg>
      </button>

      <button
        :if={@page.allow_destructive_actions}
        disabled={@data_migration.status == :up}
        class="btn btn-primary"
        phx-click="are-you-sure-up"
      >
        Migrate up
      </button>

      <button
        :if={@page.allow_destructive_actions}
        disabled={@data_migration.status == :down}
        class="btn btn-primary"
        phx-click="are-you-sure-down"
      >
        Migrate down
      </button>

      <div
        :if={@page.allow_destructive_actions and @are_you_sure_down == false}
        style="display: inline-block"
      >
        Are you sure?
        <button
          class="btn btn-primary"
          phx-click="migrate-down"
          phx-value-id={@data_migration.id}
          phx-value-repo={inspect(@data_migration.repo)}
          phx-value-folder={@data_migration.folder}
        >
          Yes, I'm sure!
        </button>
      </div>

      <div
        :if={@page.allow_destructive_actions and @are_you_sure_up == false}
        style="display: inline-block"
      >
        Are you sure?
        <button
          class="btn btn-primary"
          phx-click="migrate-up"
          phx-value-id={@data_migration.id}
          phx-value-repo={inspect(@data_migration.repo)}
          phx-value-folder={@data_migration.folder}
        >
          Yes, I'm sure!
        </button>
      </div>

      <style>
        .data-migration-status {
          min-width: 4rem;
          text-align: center;
          border-radius: 3px;
          display: inline-block;
          font-weight: 700;
          padding: 0 0.25rem;
          transition-property: color, background-color;
          transition-duration: 300ms;
          transition-timing-function: cubic-bezier(0,0,.2,1);
        }

        [data-status='up'] {
          color: #343a40;
          background-color: oklch(0.871 0.15 154.449);
        }

        [data-status='down'] {
          color: #f8f9fa;
          background-color: oklch(0.704 0.191 22.216);
        }
      </style>

      <div class="mt-4 mb-4">
        <span style="font-weight: 700">Status</span>
        <span class="data-migration-status" data-status={@data_migration.status}>
          {@data_migration.status}
        </span>
      </div>

      <dl>
        <%= for {k, v} <- [
          {"ID / Version", @data_migration.id},
          {"File", [@data_migration.folder, "/", to_string(@data_migration.id), "_", @data_migration.name, ".exs"]},
          {"Module", inspect(@data_migration.module)},
          {"Repo", inspect(@data_migration.repo)}
        ] do %>
          <dt>{k}</dt>
          <dd>
            <pre style="color: #212529; user-select: all;" class="code-field text-monospace">{v}</pre>
          </dd>
        <% end %>
        <dt>Content</dt>
        <dd>
          <pre
            style="color: #212529; user-select: all; resize: vertical; overflow-y: scroll; white-space: pre;"
            class="code-field text-monospace"
          >{@data_migration.content}</pre>
        </dd>
      </dl>
    </div>
    """
  end

  attr(:stream, :any, required: true)
  attr(:logs_present, :boolean, default: false)

  def event_logs(assigns) do
    ~H"""
    <div :if={@logs_present}>
      <style>
        #migration-logger-messages pre:hover {
          background-color: rgba(237, 237, 237, .5);
        }
        #migration-logger-messages pre {
          color: oklch(0.446 0.043 257.281);
          font-size: 0.75rem;
          margin-bottom: 0;
          padding: 0.25rem;
          user-select: all;
        }

        #migration-logger-messages  pre.log-level-debug {
          color: rgba(85, 91, 104, .75);
        }

        #migration-logger-messages pre.log-level-warning,
        #migration-logger-messages pre.log-level-warn {
          color: oklch(0.554 0.135 66.442);
        }

        #migration-logger-messages pre.log-level-error,
        #migration-logger-messages pre.log-level-critical,
        #migration-logger-messages pre.log-level-alert,
        #migration-logger-messages pre.log-level-emergency {
          color: oklch(0.444 0.177 26.899);
        }
      </style>

      <h5 class="card-title">Logs</h5>

      <div class="card mb-4">
        <div class="p-2" id="migration-logger-messages" phx-update="stream">
          <%= for {id, {message, level}} <- @stream do %>
            <pre id={id} class={"log-level-#{level} text-wrap"}><%= message %></pre>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl PageBuilder
  def handle_event("are-you-sure-up", _event, socket) do
    toggle = if is_nil(socket.assigns.are_you_sure_up), do: false
    {:noreply, assign(socket, are_you_sure_down: nil, are_you_sure_up: toggle)}
  end

  def handle_event("are-you-sure-down", _event, socket) do
    toggle = if is_nil(socket.assigns.are_you_sure_down), do: false
    {:noreply, assign(socket, are_you_sure_down: toggle, are_you_sure_up: nil)}
  end

  def handle_event(
        "migrate-up",
        %{"id" => id, "repo" => repo, "folder" => folder} = _event,
        socket
      ) do
    data_migration =
      find_migration(socket.assigns.data_migrations, id, folder, repo)

    try do
      :ok =
        DataMigration.Logger.add(
          id,
          socket.assigns.opts.pubsub,
          socket.assigns.opts.topic,
          socket.assigns.opts.listen_to ++ [{data_migration.module}]
        )

      socket =
        case Ecto.Migrator.up(
               data_migration.repo,
               data_migration.id,
               data_migration.module,
               strict_version_order: false
             ) do
          :already_up ->
            push_log(socket, :info, "Migration #{data_migration.name} already up")

          :ok ->
            socket
        end

      {data_migration, data_migrations} =
        update_status(socket.assigns.data_migrations, data_migration, :up)

      {:noreply,
       assign(
         socket,
         are_you_sure_up: nil,
         are_you_sure_down: nil,
         data_migration: data_migration,
         data_migrations: data_migrations
       )}
    rescue
      e ->
        {:noreply,
         socket
         |> assign(are_you_sure_up: nil, are_you_sure_down: nil)
         |> push_log(:error, "Migration #{data_migration.name} failed")
         |> push_log(:error, exception_message(e))}
    after
      DataMigration.Logger.remove(id)
    end
  end

  def handle_event(
        "migrate-down",
        %{"id" => id, "repo" => repo, "folder" => folder} = _event,
        socket
      ) do
    data_migration =
      find_migration(socket.assigns.data_migrations, id, folder, repo)

    try do
      :ok =
        DataMigration.Logger.add(
          id,
          socket.assigns.opts.pubsub,
          socket.assigns.opts.topic,
          socket.assigns.opts.listen_to ++ [{data_migration.module}]
        )

      socket =
        case Ecto.Migrator.down(
               data_migration.repo,
               data_migration.id,
               data_migration.module,
               strict_version_order: false
             ) do
          :already_down ->
            push_log(socket, :info, "Migration #{data_migration.name} already down")

          :ok ->
            socket
        end

      {data_migration, data_migrations} =
        update_status(socket.assigns.data_migrations, data_migration, :down)

      {:noreply,
       assign(socket,
         are_you_sure_up: nil,
         are_you_sure_down: nil,
         data_migration: data_migration,
         data_migrations: data_migrations
       )}
    rescue
      e ->
        {:noreply,
         socket
         |> assign(are_you_sure_down: nil)
         |> assign(are_you_sure_up: nil)
         |> push_log(:error, "Migration #{data_migration.name} failed")
         |> push_log(:error, exception_message(e))}
    after
      DataMigration.Logger.remove(id)
    end
  end

  def handle_event("navigate", %{"action" => "list"}, socket) do
    params = %{action: "index"}

    {:noreply,
     socket
     |> assign(data_migration: nil, are_you_sure_up: nil, are_you_sure_down: nil)
     |> push_patch(to: live_dashboard_path(socket, socket.assigns.page, params))}
  end

  def handle_event("navigate", %{"id" => id, "repo" => repo, "folder" => folder} = _event, socket) do
    params = %{action: "show", id: id, repo: repo, folder: folder}

    {:noreply, push_patch(socket, to: live_dashboard_path(socket, socket.assigns.page, params))}
  end

  @impl true
  def handle_info({DataMigration.Logger, {:logger, level, message}}, socket) do
    # Remove ANSI color codes designed for terminal output
    message =
      message
      |> IO.iodata_to_binary()
      |> String.replace(~r/\[\d{1,2}m/, "")
      |> String.replace(~r/(\\n)+/, " ")

    {:noreply,
     socket
     |> assign(:logs_present, true)
     |> stream_insert(:logs, {message, level})}
  end

  defp maybe_recompile([]), do: []

  if Mix.env() == :dev do
    defp maybe_recompile(migrations) do
      Enum.each(migrations, fn migration ->
        Code.unrequire_files([migration.file])
        :code.soft_purge(migration.module)
      end)

      []
    end
  else
    defp maybe_recompile(migrations), do: migrations
  end

  defp compile_file(file, folder) do
    # Silence "redefining module ..." logs
    {result, _} =
      Code.with_diagnostics(fn ->
        Code.require_file(file, folder)
      end)

    result
  end

  defp push_log(socket, level, message) do
    socket
    |> assign(logs_present: true)
    |> stream_insert(:logs, {"[#{level}] #{message}", level})
  end

  defp row_fetcher(migrations, params, _node) do
    found =
      migrations
      |> search(params[:search])
      |> Enum.sort_by(
        & &1[Map.get(params, :sort_by, :status)],
        params[:sort_dir] || :asc
      )

    {found, length(migrations)}
  end

  @searchable ~w[id name file module otp_app repo]a
  defp search(migrations, empty) when empty in ["", nil], do: migrations

  defp search(migrations, term) do
    Enum.filter(migrations, fn migration ->
      Enum.any?(@searchable, &String.contains?(inspect(migration[&1]), term))
    end)
  end

  @cache_key :data_migration_list
  defp list_data_migrations(locations) do
    existing = @cache_key |> :persistent_term.get([]) |> maybe_recompile()

    migrations =
      Enum.reduce(locations, existing, fn {repo, folders}, acc ->
        Enum.reduce(List.wrap(folders), acc, fn folder, data_migration_acc ->
          abs_dir = Ecto.Migrator.migrations_path(repo, folder)
          app_dir = Application.app_dir(repo.config()[:otp_app])
          [_, rel_path] = String.split(abs_dir, app_dir <> "/", parts: 2)

          statuses =
            repo
            |> Ecto.Migrator.migrations(abs_dir, skip_table_creation: true, migration_lock: false)
            |> Enum.reduce(%{}, fn
              {_status, _id, "** FILE NOT FOUND **"}, acc -> acc
              {status, id, _name}, acc -> Map.put(acc, id, status)
            end)

          data_migrations =
            [abs_dir, "*.exs"]
            |> Path.join()
            |> Path.wildcard()
            |> Enum.flat_map(fn file ->
              case compile_file(file, abs_dir) do
                nil -> []
                compiled -> to_migration(file, rel_path, repo, compiled, statuses)
              end
            end)

          data_migrations ++ data_migration_acc
        end)
      end)

    :persistent_term.put(@cache_key, migrations)
    migrations
  end

  # Skipped because this is a compile-controlled list of files not from user input
  # sobelow_skip ["Traversal"]
  defp to_migration(file, folder, repo, compiled, statuses) do
    [id, name] = String.split(Path.basename(file, ".exs"), "_", parts: 2)

    Enum.map(compiled, fn {mod, _beam} ->
      %{
        id: String.to_integer(id),
        name: name,
        file: file,
        folder: folder,
        status: statuses[String.to_integer(id)],
        content: File.read!(file),
        module: mod,
        repo: repo,
        otp_app: repo.config()[:otp_app]
      }
    end)
  end

  defp find_migration(migrations, id, folder, repo) do
    Enum.find(migrations, fn migration ->
      migration.id == String.to_integer(id) and
        migration.folder == folder and
        migration.repo == String.to_existing_atom("Elixir." <> repo)
    end)
  end

  # This is only ignored because of dialyzer also ignoring `DataMigration.Logger.add/4`
  @dialyzer {:nowarn_function, update_status: 3}
  defp update_status(migrations, nil, _status), do: {nil, migrations}

  defp update_status(migrations, migration, status) do
    %{id: id, repo: repo, folder: folder} = migration

    {%{migration | status: status},
     Enum.map(migrations, fn
       %{id: ^id, repo: ^repo, folder: ^folder} = migration -> %{migration | status: status}
       migration -> migration
     end)}
  end

  defp list_row_attrs(data_migration) do
    [
      {"phx-click", "navigate"},
      {"phx-value-id", data_migration[:id]},
      {"phx-value-repo", inspect(data_migration[:repo])},
      {"phx-value-folder", data_migration[:folder]}
    ]
  end

  if Code.ensure_loaded?(Postgrex) do
    defp exception_message(%Postgrex.Error{query: query} = e) when is_binary(query) do
      e = %{e | query: String.replace(query, ~r/(\n)+/, " ")}
      inspect(e, printable_limit: :infinity)
    end
  end

  defp exception_message(e), do: inspect(e, printable_limit: :infinity)
end
