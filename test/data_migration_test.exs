defmodule DataMigrationTest do
  # Not async: the migrator runs `up/0` in a process of its own, which the
  # sandbox's shared mode hands the test's connection. SQLite also takes one
  # writer at a time, and every test here writes `schema_migrations`.
  use DataMigration.ConnCase, async: false

  # `migration_lock: false`: the lock holds the sandbox's connection while the
  # migrator runs `up/0` from a second process that needs it too.
  @opts [migration_lock: false, log: false]

  setup do
    listener = :"data_migration_test_#{System.unique_integer([:positive])}"
    Process.register(self(), listener)
    {:ok, listener: listener}
  end

  describe "pending/2" do
    @tag :tmp_dir
    test "lists the data migrations that have not run, oldest first", ctx do
      write_migration(ctx, 1_001, "newer")
      write_migration(ctx, 1_000, "older")
      write_migration(ctx, 1_002, "ran")

      assert DataMigration.run(ctx.repo, 1_002, ctx.tmp_dir, @opts) == :ok

      assert DataMigration.pending(ctx.repo, ctx.tmp_dir) == [{1_000, "older"}, {1_001, "newer"}]
    end

    @tag :tmp_dir
    test "does not list a repeatable data migration once it has run", ctx do
      write_migration(ctx, 1_000, "repeatable", "use DataMigration, repeatable: true")

      assert DataMigration.pending(ctx.repo, ctx.tmp_dir) == [{1_000, "repeatable"}]
      assert DataMigration.run(ctx.repo, 1_000, ctx.tmp_dir, @opts) == :ok
      assert DataMigration.pending(ctx.repo, ctx.tmp_dir) == []
    end
  end

  describe "run/4" do
    @tag :tmp_dir
    test "runs the data migration with the version given and no other", ctx do
      write_migration(ctx, 1_000, "older")
      write_migration(ctx, 1_001, "target")

      assert DataMigration.run(ctx.repo, 1_001, ctx.tmp_dir, @opts) == :ok

      assert_received {:ran, 1_001}
      refute_received {:ran, 1_000}
      assert DataMigration.pending(ctx.repo, ctx.tmp_dir) == [{1_000, "older"}]
    end

    @tag :tmp_dir
    test "runs nothing for a version no file has", ctx do
      write_migration(ctx, 1_000, "other")

      assert DataMigration.run(ctx.repo, 1_001, ctx.tmp_dir, @opts) == {:error, :not_found}

      refute_received {:ran, _version}
    end

    @tag :tmp_dir
    test "runs nothing for a version two files share", ctx do
      write_migration(ctx, 1_000, "first")
      write_migration(ctx, 1_000, "second")

      assert DataMigration.run(ctx.repo, 1_000, ctx.tmp_dir, @opts) ==
               {:error, :duplicate_version}

      refute_received {:ran, _version}
    end

    @tag :tmp_dir
    test "refuses to run a one-shot data migration a second time", ctx do
      write_migration(ctx, 1_000, "ecto_migration", "use Ecto.Migration")
      write_migration(ctx, 1_001, "data_migration", "use DataMigration")

      for version <- [1_000, 1_001] do
        assert DataMigration.run(ctx.repo, version, ctx.tmp_dir, @opts) == :ok

        assert DataMigration.run(ctx.repo, version, ctx.tmp_dir, @opts) ==
                 {:error, :already_applied}

        assert_received {:ran, ^version}
        refute_received {:ran, ^version}
      end
    end

    @tag :tmp_dir
    test "runs a repeatable data migration again", ctx do
      write_migration(ctx, 1_000, "repeatable", "use DataMigration, repeatable: true")

      assert DataMigration.run(ctx.repo, 1_000, ctx.tmp_dir, @opts) == :ok
      assert DataMigration.run(ctx.repo, 1_000, ctx.tmp_dir, @opts) == :ok

      assert_received {:ran, 1_000}
      assert_received {:ran, 1_000}
      assert DataMigration.pending(ctx.repo, ctx.tmp_dir) == []
    end

    @tag :tmp_dir
    test "leaves a repeatable data migration pending when running it again raises", ctx do
      fail_flag = Path.join(ctx.tmp_dir, "fail")

      write_migration(ctx, 1_000, "repeatable", "use DataMigration, repeatable: true", """
      if File.exists?(#{inspect(fail_flag)}), do: raise("failed on purpose")
      """)

      assert DataMigration.run(ctx.repo, 1_000, ctx.tmp_dir, @opts) == :ok
      File.write!(fail_flag, "")

      assert_raise RuntimeError, "failed on purpose", fn ->
        DataMigration.run(ctx.repo, 1_000, ctx.tmp_dir, @opts)
      end

      assert DataMigration.pending(ctx.repo, ctx.tmp_dir) == [{1_000, "repeatable"}]
    end
  end

  describe "repeatable?/1" do
    test "is true only for a migration declared repeatable" do
      [{ecto_migration, _}] = compile_module("use Ecto.Migration")
      [{one_shot, _}] = compile_module("use DataMigration")
      [{repeatable, _}] = compile_module("use DataMigration, repeatable: true")

      refute DataMigration.repeatable?(ecto_migration)
      refute DataMigration.repeatable?(one_shot)
      assert DataMigration.repeatable?(repeatable)
      refute DataMigration.repeatable?(Enum)
    end

    test "use DataMigration rejects an option it does not know" do
      assert_raise ArgumentError, ~r/:repeatable must be true or false/, fn ->
        compile_module("use DataMigration, repeatable: :yes")
      end

      assert_raise ArgumentError, ~r/unknown keys \[:one_shot\]/, fn ->
        compile_module("use DataMigration, one_shot: true")
      end
    end
  end

  defp write_migration(ctx, version, name, use_line \\ "use Ecto.Migration", before_send \\ "") do
    module = Module.concat([__MODULE__, "M#{:erlang.phash2({ctx.test, version, name})}"])

    File.write!(Path.join(ctx.tmp_dir, "#{version}_#{name}.exs"), """
    defmodule #{inspect(module)} do
      #{use_line}

      def up do
        #{before_send}
        send(#{inspect(ctx.listener)}, {:ran, #{version}})
        :ok
      end

      def down, do: :ok
    end
    """)
  end

  defp compile_module(use_line) do
    module = Module.concat([__MODULE__, "Compiled#{System.unique_integer([:positive])}"])

    Code.compile_string("""
    defmodule #{inspect(module)} do
      #{use_line}

      def up, do: :ok
      def down, do: :ok
    end
    """)
  end
end
