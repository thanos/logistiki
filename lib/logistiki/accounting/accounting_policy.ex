defmodule Logistiki.Accounting.AccountingPolicy do
  @moduledoc """
  A record of the accounting policy selected for an event.

  Policies are selected by the knowledge layer (`Logistiki.Knowledge.Program`)
  and recorded on the journal for explanation and replay.
  """

  defstruct [:name, :description]

  @type t :: %__MODULE__{name: atom(), description: String.t() | nil}
end
