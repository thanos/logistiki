import Config

config :logistiki, ecto_repos: [Logistiki.Repo]

config :logistiki, :ledger_backend, Logistiki.Ledger.Simulation

config :logistiki, :knowledge_program, Logistiki.Knowledge.Program

config :beancount_ex,
  engine: Beancount.Engine.Elixir,
  bean_check_path: "bean-check",
  bean_query_path: "bean-query"

config :beancount_ex, Beancount.Repo,
  database: ":memory:",
  pool_size: 1,
  migration_source: "beancount_schema_migrations"

config :logistiki, Logistiki.Repo,
  username: System.get_env("LOGISTIKI_DB_USER", "thanos"),
  password: System.get_env("LOGISTIKI_DB_PASSWORD", ""),
  hostname: System.get_env("LOGISTIKI_DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("LOGISTIKI_DB_PORT", "5432"))

import_config "#{config_env()}.exs"
