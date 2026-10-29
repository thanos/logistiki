defmodule Logistiki.DataCase do
  @moduledoc """
  Shared test context for Ecto-backed tests.

  Provides a sandboxed `Logistiki.Repo` and helpers for building data.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Logistiki.BusinessEntities
  alias Logistiki.Knowledge.Program
  alias Logistiki.Relationships
  alias Logistiki.Repo
  alias Logistiki.VirtualAccounts

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
    pid = Sandbox.start_owner!(Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end

  @doc "Returns the demo knowledge program module."
  def knowledge_program, do: Program

  @doc "Ensures all demo context modules are loaded."
  def ensure_loaded do
    [BusinessEntities, VirtualAccounts, Relationships]
  end

  @doc "Extracts errors from a changeset as a keyword list of fields to messages."
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, _opts} -> message end)
  end
end
