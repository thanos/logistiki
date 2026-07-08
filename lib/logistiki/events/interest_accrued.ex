defmodule Logistiki.Event.InterestAccrued do
  @moduledoc """
  Interest accrued on a client account.

  Accounting impact: debit interest expense, credit client liability.

  ## Fields

  Inherits all common fields from `Logistiki.Event` plus:

    * `interest_expense_account_code` — `String.t() | nil` — the interest
      expense account code (e.g. `"EXPENSES:INTEREST"`). If not provided, the
      knowledge layer resolves this role via a static mapping.

  ## Example

      %Logistiki.Event.InterestAccrued{
        id: "evt_004",
        entity_type: "corporate",
        account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
        interest_expense_account_code: "EXPENSES:INTEREST",
        amount: Decimal.new("5.00"),
        currency: "USD",
        effective_date: ~D[2026-07-07]
      }
  """

  use Logistiki.Event, type: "interest_accrued"

  defevent do
    field(:interest_expense_account_code, :string)
  end
end
