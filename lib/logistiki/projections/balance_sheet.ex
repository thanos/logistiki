defmodule Logistiki.Projections.BalanceSheet do
  @moduledoc """
  A balance sheet view: assets, liabilities, and equity balances.

  Each section is a list of `Logistiki.Projections.Balance` structs (one per
  account per currency) plus a section total per currency.
  """

  @type section :: %{
          balances: [Logistiki.Projections.Balance.t()],
          totals_by_currency: %{String.t() => Decimal.t()}
        }

  @typedoc """
  The struct type. See the module documentation for field details and examples.
  """
  @type t :: %__MODULE__{
          assets: section(),
          liabilities: section(),
          equity: section(),
          totals_by_currency: %{
            String.t() => %{assets: Decimal.t(), liabilities: Decimal.t(), equity: Decimal.t()}
          }
        }

  defstruct assets: %{balances: [], totals_by_currency: %{}},
            liabilities: %{balances: [], totals_by_currency: %{}},
            equity: %{balances: [], totals_by_currency: %{}},
            totals_by_currency: %{}
end
