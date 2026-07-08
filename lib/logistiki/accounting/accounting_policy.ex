defmodule Logistiki.Accounting.AccountingPolicy do
  @moduledoc """
  A record of the accounting policy selected for an event.

  Policies are selected by the knowledge layer (`Logistiki.Knowledge.Program`)
  and recorded on the journal for explanation and replay.

  ## Fields

    * `name` — `atom()` — the policy name (e.g. `:cash_deposit`,
      `:corporate_wire_fee`)
    * `description` — `String.t() | nil` — optional human-readable description

  ## Example

      %Logistiki.Accounting.AccountingPolicy{
        name: :cash_deposit,
        description: "Debit cash, credit client liability"
      }
  """

  defstruct [:name, :description]

  @typedoc """
  The struct type. See the module documentation for field details and examples.
  """
  @type t :: %__MODULE__{name: atom(), description: String.t() | nil}
end
