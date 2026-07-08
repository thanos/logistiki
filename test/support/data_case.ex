defmodule Logistiki.DataCase do
  @moduledoc """
  Shared test context for Ecto-backed tests.

  Provides a sandboxed `Logistiki.Repo` and helpers for building data.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Logistiki.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Logistiki.DataCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Logistiki.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  @doc "Returns the demo knowledge program module."
  def knowledge_program, do: Logistiki.Knowledge.Program

  @doc "Ensures all demo context modules are loaded."
  def ensure_loaded do
    [Logistiki.BusinessEntities, Logistiki.VirtualAccounts, Logistiki.Relationships]
  end

  @doc "Extracts errors from a changeset as a keyword list of fields to messages."
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
