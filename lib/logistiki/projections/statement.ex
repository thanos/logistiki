defmodule Logistiki.Projections.StatementLine do
  @moduledoc """
  A single line in an account statement.

  Includes a running balance so statements read like a real account ledger.
  """

  @typedoc """
  The struct type. See the module documentation for field details and examples.
  """
  @type t :: %__MODULE__{
          journal_id: term() | nil,
          posting_id: term() | nil,
          event_id: String.t() | nil,
          date: Date.t() | nil,
          description: String.t() | nil,
          account_code: String.t(),
          debit: Decimal.t() | nil,
          credit: Decimal.t() | nil,
          amount: Decimal.t() | nil,
          currency: String.t(),
          running_balance: Decimal.t() | nil,
          source_system: String.t() | nil,
          source_id: String.t() | nil,
          selected_policy: String.t() | nil,
          selected_template: String.t() | nil,
          metadata: map()
        }

  defstruct [
    :journal_id,
    :posting_id,
    :event_id,
    :date,
    :description,
    :account_code,
    :debit,
    :credit,
    :amount,
    :currency,
    :running_balance,
    :source_system,
    :source_id,
    :selected_policy,
    :selected_template,
    metadata: %{}
  ]
end
