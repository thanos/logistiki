defmodule Logistiki.Projections.IncomeStatement do
  @moduledoc """
  An income statement view: income and expense balances, plus net profit per
  currency.
  """

  @type section :: %{
          balances: [Logistiki.Projections.Balance.t()],
          totals_by_currency: %{String.t() => Decimal.t()}
        }

  @type t :: %__MODULE__{
          income: section(),
          expenses: section(),
          net_profit_by_currency: %{String.t() => Decimal.t()}
        }

  defstruct income: %{balances: [], totals_by_currency: %{}},
            expenses: %{balances: [], totals_by_currency: %{}},
            net_profit_by_currency: %{}
end
