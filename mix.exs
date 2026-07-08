defmodule Logistiki.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/thanos/logistiki"

  def project do
    [
      app: :logistiki,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      package: package(),
      docs: docs(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        credo: :dev
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {Logistiki.Application, []}
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.0"},
      {:postgrex, ">= 0.0.0"},
      {:ecto_sqlite3, "~> 0.18", optional: true},
      {:ex_datalog, "~> 0.5"},
      {:beancount_ex, "~> 0.6"},
      {:decimal, "~> 3.1"},
      {:telemetry, "~> 1.0"},
      {:stream_data, "~> 1.0", only: [:test, :dev]},
      {:excoveralls, "~> 0.18", only: :test},
      {:mox, "~> 1.2", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      description: "An embedded OTP accounting engine for Elixir applications.",
      licenses: ["MIT"],
      maintainers: ["Thanos Vassilakis"],
      files: ~w(lib docs .formatter.exs mix.exs README.md CHANGELOG.md LICENSE),
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/livebooks/logistiki_demo.livemd",
        "LICENSE" | Path.wildcard("docs/**/*.md")
      ],
      source_url: @source_url,
      source_ref: "v#{@version}",
      groups_for_modules: [
        "Public API": [Logistiki],
        "Business Events": [Logistiki.Event, Logistiki.Event.Normalized, Logistiki.Events],
        "Knowledge Layer": [
          Logistiki.Knowledge,
          Logistiki.Knowledge.Program,
          Logistiki.Knowledge.KnowledgeBase,
          Logistiki.Knowledge.Facts,
          Logistiki.Knowledge.Query,
          Logistiki.Knowledge.Result,
          Logistiki.Knowledge.Rules,
          Logistiki.Knowledge.PolicySelector,
          Logistiki.Knowledge.TemplateResolver
        ],
        Accounting: [
          Logistiki.Accounting,
          Logistiki.Accounting.Journal,
          Logistiki.Accounting.Posting,
          Logistiki.Accounting.Money,
          Logistiki.Accounting.Result,
          Logistiki.Accounting.Pipeline,
          Logistiki.Accounting.JournalBuilder,
          Logistiki.Accounting.PostingBuilder,
          Logistiki.Accounting.InvariantValidator,
          Logistiki.Accounting.AccountingPolicy,
          Logistiki.Accounting.AccountingTemplate
        ],
        "Ledger Backends": [
          Logistiki.Ledger,
          Logistiki.Ledger.Behaviour,
          Logistiki.Ledger.Result,
          Logistiki.Ledger.Simulation,
          Logistiki.Ledger.Beancount,
          Logistiki.Ledger.BeancountMapper
        ],
        Projections: [
          Logistiki.Projections,
          Logistiki.Projections.Balance,
          Logistiki.Projections.StatementLine,
          Logistiki.Projections.TrialBalance,
          Logistiki.Projections.GeneralLedger,
          Logistiki.Projections.BalanceSheet,
          Logistiki.Projections.IncomeStatement,
          Logistiki.Projections.ProjectionEngine
        ],
        Entities: [
          Logistiki.BusinessEntities,
          Logistiki.BusinessEntities.BusinessEntity,
          Logistiki.BusinessEntities.BusinessEntityClosure,
          Logistiki.VirtualAccounts,
          Logistiki.VirtualAccounts.VirtualAccount,
          Logistiki.VirtualAccounts.VirtualAccountClosure,
          Logistiki.Relationships,
          Logistiki.Relationships.EntityAccount
        ],
        Audit: [
          Logistiki.Audit,
          Logistiki.Audit.AuditEvent,
          Logistiki.Audit.Evidence
        ],
        Infrastructure: [
          Logistiki.Repo,
          Logistiki.Application,
          Logistiki.Error,
          Logistiki.Telemetry,
          Logistiki.Demo,
          Logistiki.Demo.Seeds
        ]
      ]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
