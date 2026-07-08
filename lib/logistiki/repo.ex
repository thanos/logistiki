defmodule Logistiki.Repo do
  @moduledoc """
  The Ecto repository backing Logistiki.

  The adapter is selected at compile time from the `:logistiki` application env,
  defaulting to `Ecto.Adapters.Postgres`. Set the `LOGISTIKI_DB_ADAPTER` env
  variable to `"sqlite"` before compilation to use `Ecto.Adapters.SQLite3`
  (useful for Livebooks and tests that want an in-memory database).

  ## PostgreSQL (default)

      config :logistiki, Logistiki.Repo,
        database: "logistiki_dev",
        hostname: "localhost"

  ## SQLite (for Livebooks)

      config :logistiki, Logistiki.Repo,
        adapter: Ecto.Adapters.SQLite3,
        database: ":memory:",
        pool_size: 1

  In tests, the sandbox pool is enabled automatically via `config/test.exs`.
  """

  adapter =
    case System.get_env("LOGISTIKI_DB_ADAPTER", "postgres") do
      "sqlite" -> Ecto.Adapters.SQLite3
      _ -> Ecto.Adapters.Postgres
    end

  use Ecto.Repo,
    otp_app: :logistiki,
    adapter: adapter
end
