defmodule Logistiki.Projections.TrialBalance do
  @moduledoc """
  A trial balance: debit/credit totals per account per currency.

  Debits and credits must balance per currency (`balanced` flag).
  """

  @type line :: %{
          account_code: String.t(),
          account_name: String.t() | nil,
          debit_total: Decimal.t(),
          credit_total: Decimal.t(),
          net: Decimal.t(),
          currency: String.t()
        }

  @type t :: %__MODULE__{
          lines: [line()],
          currencies: [String.t()],
          balanced: boolean()
        }

  defstruct lines: [], currencies: [], balanced: true
end
