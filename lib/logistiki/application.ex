defmodule Logistiki.Application do
  @moduledoc false

  use Application

  @doc false
  @impl true
  @spec start(Application.start_type(), term()) :: Supervisor.on_start()
  def start(_type, _args) do
    children = [
      Logistiki.Repo
    ]

    # v0.1.0 prefers deterministic functions and persisted state over
    # long-running processes. A knowledge-program cache and projection
    # supervisor are future work (see docs/vision.md roadmap).
    opts = [strategy: :one_for_one, name: Logistiki.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
