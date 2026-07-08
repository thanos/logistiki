defmodule Logistiki.Event.RefundIssued do
  @moduledoc """
  A refund issued to a customer. Accounting impact mirrors a withdrawal:
  debit client liability, credit cash.

  ## Fields

  Inherits all common fields from `Logistiki.Event` plus:

    * `cash_account_code` — `String.t() | nil` — the cash/nostro account code
      (e.g. `"ASSETS:CASH:USD:NOSTRO"`)

  ## Example

      %Logistiki.Event.RefundIssued{
        id: "evt_005",
        entity_type: "corporate",
        account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
        cash_account_code: "ASSETS:CASH:USD:NOSTRO",
        amount: Decimal.new("100.00"),
        currency: "USD",
        effective_date: ~D[2026-07-07]
      }
  """

  use Logistiki.Event, type: "refund_issued"

  defevent do
    field :cash_account_code, :string
  end
end
