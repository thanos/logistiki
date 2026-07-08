defmodule Logistiki.Event.InterestAccrued do
  @moduledoc """
  Interest accrued on a client account.

  Accounting impact: debit interest expense, credit client liability.
  """

  use Logistiki.Event, type: "interest_accrued"

  defevent do
    field :interest_expense_account_code, :string
  end
end
