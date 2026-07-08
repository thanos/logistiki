defmodule Logistiki.Ledger.Result do
  @moduledoc """
  The result of a ledger backend execution.

  Backends return this struct so the runtime can record what happened without
  leaking backend-specific types.
  """

  @type t :: %__MODULE__{
          backend: module(),
          journal_id: term() | nil,
          status: :ok | :error,
          posted_at: DateTime.t() | nil,
          balances: map(),
          details: map()
        }

  defstruct [:backend, :journal_id, :status, :posted_at, balances: %{}, details: %{}]
end
