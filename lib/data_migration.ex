defmodule DataMigration do
  @moduledoc """
  Lists data migrations that have not run, runs one by version, and marks a
  data migration as one-shot or repeatable.

  A data migration is an `Ecto.Migration` kept in a folder of its own, such as
  `priv/repo/data_migrations`, and recorded in the repo's `schema_migrations`
  table like any other migration. `DataMigration.LiveDashboard.Page` shows them
  on a LiveDashboard page.

  `paths` below are directories, as `Ecto.Migrator.migrations/3` takes them.
  `Ecto.Migrator.migrations_path(repo, "data_migrations")` gives the usual one.

  ## One-shot and repeatable

      defmodule MyApp.Repo.DataMigrations.MirrorAvatars do
        use DataMigration, repeatable: true

        def up, do: MyApp.Avatars.mirror_all()
        def down, do: :ok
      end

  `use DataMigration` is `use Ecto.Migration` plus that annotation. A data
  migration is one-shot unless it says `repeatable: true`, and so is one that
  uses `Ecto.Migration` directly. Either kind is pending until it has run once.
  `run/4` refuses to run a one-shot data migration a second time, and runs a
  repeatable one again.
  """

  import Ecto.Query, only: [from: 2]

  defmacro __using__(opts) do
    opts = Keyword.validate!(opts, repeatable: false)
    repeatable? = Keyword.fetch!(opts, :repeatable)

    if not is_boolean(repeatable?) do
      raise ArgumentError, ":repeatable must be true or false, got: #{inspect(repeatable?)}"
    end

    quote do
      use Ecto.Migration

      @doc false
      def __data_migration__, do: [repeatable: unquote(repeatable?)]
    end
  end

  @doc """
  Whether the migration `module` was declared with `use DataMigration, repeatable: true`.
  """
  def repeatable?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__data_migration__, 0) and
      Keyword.get(module.__data_migration__(), :repeatable, false)
  end

  @doc """
  The data migrations in `paths` that have not run, oldest first, as
  `{version, name}`.

  Reads the recorded versions without taking the migration lock, so a deploy
  that holds it does not block the caller, and without creating the
  `schema_migrations` table.
  """
  def pending(repo, paths) do
    repo
    |> Ecto.Migrator.migrations(List.wrap(paths),
      skip_table_creation: true,
      migration_lock: false
    )
    |> Enum.flat_map(fn
      {:down, version, name} -> [{version, name}]
      {:up, _version, _name} -> []
    end)
  end

  @doc """
  Runs the data migration with `version` in `paths`, and no other.

  Returns `:ok` once it has run. Otherwise it runs nothing and returns:

    * `{:error, :not_found}` when no file in `paths` has `version`.
    * `{:error, :duplicate_version}` when more than one does.
    * `{:error, :already_applied}` when the data migration is one-shot and has
      run.

  A repeatable data migration that has run is run again: its row in
  `schema_migrations` is deleted, then `Ecto.Migrator.up/4` runs it and records
  it again. If that run raises, the row stays deleted, so the data migration is
  pending.

  `opts` are passed to `Ecto.Migrator.up/4`.
  """
  def run(repo, version, paths, opts \\ []) when is_integer(version) do
    with {:ok, file} <- find_file(paths, version) do
      module = migration_module(file)

      case up(repo, version, module, opts) do
        {:error, :already_applied} = refused -> maybe_rerun(repo, version, module, opts, refused)
        :ok -> :ok
      end
    end
  end

  defp maybe_rerun(repo, version, module, opts, refused) do
    if repeatable?(module) do
      forget(repo, version, opts)
      up(repo, version, module, opts)
    else
      refused
    end
  end

  defp up(repo, version, module, opts) do
    case Ecto.Migrator.up(repo, version, module, opts) do
      :ok -> :ok
      :already_up -> {:error, :already_applied}
    end
  end

  defp find_file(paths, version) do
    paths
    |> List.wrap()
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "#{version}_*.exs")))
    |> case do
      [file] -> {:ok, file}
      [] -> {:error, :not_found}
      [_ | _] -> {:error, :duplicate_version}
    end
  end

  # Code.compile_file/1 redefines a module that is already loaded, which is what
  # a second run of the same file needs. Its "redefining module" warning is
  # expected here, so it is captured rather than printed.
  defp migration_module(file) do
    {compiled, _diagnostics} = Code.with_diagnostics(fn -> Code.compile_file(file) end)

    Enum.find_value(compiled, fn {module, _binary} ->
      function_exported?(module, :__migration__, 0) && module
    end) ||
      raise Ecto.MigrationError, "#{Path.relative_to_cwd(file)} does not define an Ecto.Migration"
  end

  # The same delete `Ecto.Migrator.down/4` makes, without running `down/0`.
  defp forget(repo, version, opts) do
    config = repo.config()
    migration_repo = Keyword.get(config, :migration_repo, repo)
    source = Keyword.get(config, :migration_source, "schema_migrations")

    migration_repo.delete_all(
      from(m in source, where: m.version == type(^version, :integer)),
      prefix: opts[:prefix],
      timeout: :infinity,
      log: Keyword.get(opts, :log_migrator_sql, false),
      schema_migration: true,
      ecto_query: :schema_migration,
      telemetry_options: [schema_migration: true]
    )
  end
end
