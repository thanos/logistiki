defmodule Logistiki.Repo do
  use Ecto.Repo,
    otp_app: :logistiki,
    adapter: Ecto.Adapters.Postgres
end
