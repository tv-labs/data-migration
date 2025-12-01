defmodule DataMigration.MixProject do
  use Mix.Project
  @version "0.1.0"
  @source_url "https://github.com/tv-labs/data-migration"
  @adapters ~w[pg myxql tds sqlite]

  def project do
    [
      app: :data_migration,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: "Manage Data Migrations with Ecto and Phoenix LiveDashboard",
      package: [
        licenses: ["Apache-2.0"],
        links: %{
          "GitHub" => @source_url,
          "Changelog" => "https://github.com/tv-labs/data-migration/blob/#{@version}/CHANGELOG.md"
        }
      ],
      docs: [
        main: "DataMigration.LiveDashboard.Page",
        source_ref: @version,
        source_url: @source_url,
        assets: %{"assets" => "assets"},
        extras: ["CHANGELOG.md"]
      ],
      deps: deps(),
      preferred_cli_env: ["test.all": :test, "test.adapters": :test],
      aliases: aliases()
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
      {:ex_doc, "~> 0.34", only: :dev, runtime: false, warn_if_outdated: true},
      {:tidewave, "~> 0.4", only: :dev},
      {:lazy_html, "~> 0.1", only: [:test]},
      {:bandit, "~> 1.0", only: :dev}
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

  defp aliases do
    [
      "test.all": &test_adapters/1,
      tidewave:
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4011) end)'"
    ]
  end
end
