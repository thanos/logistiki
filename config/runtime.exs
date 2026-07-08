import Config

if config_env() == :prod do
  database_url =
    System.get_env("LOGISTIKI_DATABASE_URL") ||
      raise """
      environment variable LOGISTIKI_DATABASE_URL is missing.
      Example: ecto://postgres:postgres@localhost/logistiki_prod
      """

  config :logistiki, Logistiki.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  backend =
    System.get_env("LOGISTIKI_LEDGER_BACKEND", "Logistiki.Ledger.Beancount")
    |> String.to_atom()

  config :logistiki, :ledger_backend, backend
end
