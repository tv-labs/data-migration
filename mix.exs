defmodule DataMigration.MixProject do
  use Mix.Project

  @adapters ~w[pg myxql tds sqlite]

  def project do
    [
      app: :data_migration,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      preferred_cli_env: ["test.all": :test, "test.adapters": :test],
      aliases: [
        "test.all": ["test.adapters"],
        "test.adapters": &test_adapters/1
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 3.8"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.1"},

      # Adapters for testing
      {:postgrex, "~> 0.19 or ~> 1.0", optional: true},
      {:myxql, "~> 0.8", optional: true},
      {:ecto_sqlite3, "~> 0.17", optional: true},
      {:tds, "~> 2.2", optional: true},

      # Dev/Test
      {:lazy_html, "~> 0.1", only: [:test]}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp test_adapters(args) do
    for adapter <- @adapters, do: env_run(adapter, args)
  end

  defp env_run(adapter, args) do
    IO.puts([
      IO.ANSI.blue(),
      "==> Running tests for ECTO_ADAPTER=#{adapter} mix test",
      IO.ANSI.reset()
    ])

    mix_cmd_with_status_check(
      ["test", if(IO.ANSI.enabled?(), do: "--color", else: "--no-color") | args],
      env: [{"ECTO_ADAPTER", adapter}]
    )
  end

  defp mix_cmd_with_status_check(args, opts) do
    case System.cmd("mix", args, [into: IO.binstream(:stdio, :line)] ++ opts) do
      {_, result} when result > 0 -> System.at_exit(fn _ -> exit({:shutdown, 1}) end)
      _ -> :ok
    end
  end
end
