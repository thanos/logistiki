import Config

if url = System.get_env("LOGISTIKI_DATABASE_URL") do
  config :logistiki, Logistiki.Repo,
    url: url,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 10
else
  config :logistiki, Logistiki.Repo,
    database: "logistiki_test",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 10
end

config :logistiki, :ledger_backend, Logistiki.Ledger.Simulation

config :logger, level: :warning
