defmodule Logistiki.Event.InvoicePaid do
  @moduledoc """
  An invoice paid by a customer from their operating account.

  Accounting impact: debit counterparty, credit client.

  ## Fields

  Inherits all common fields from `Logistiki.Event` plus:

    * `cash_account_code` — `String.t() | nil` — the cash/nostro account code
    * `counterparty_account_code` — `String.t() | nil` — the counterparty's
      account code (e.g. `"LIABILITIES:CLIENT_DEPOSITS:USD:VENDOR"`)

  ## Example

      %Logistiki.Event.InvoicePaid{
        id: "evt_006",
        account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
        counterparty_account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:VENDOR",
        cash_account_code: "ASSETS:CASH:USD:NOSTRO",
        amount: Decimal.new("250.00"),
        currency: "USD",
        effective_date: ~D[2026-07-07]
      }
  """

  use Logistiki.Event, type: "invoice_paid"

  defevent do
    field :cash_account_code, :string
    field :counterparty_account_code, :string
  end
end
