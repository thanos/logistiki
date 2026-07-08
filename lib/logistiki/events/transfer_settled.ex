defmodule Logistiki.Event.TransferSettled do
  @moduledoc """
  An internal transfer settled between two accounts (e.g. operating -> payroll).

  Accounting impact: debit destination account, credit source (client liability).

  ## Fields

  Inherits all common fields from `Logistiki.Event` plus:

    * `cash_account_code` — `String.t() | nil` — the cash/nostro account
    * `destination_account_code` — `String.t() | nil` — the target account code
      (e.g. `"LIABILITIES:CLIENT_DEPOSITS:USD:ACME:PAYROLL"`)

  ## Example

      %Logistiki.Event.TransferSettled{
        id: "evt_002",
        account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
        destination_account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:PAYROLL",
        amount: Decimal.new("500.00"),
        currency: "USD",
        effective_date: ~D[2026-07-07]
      }
  """

  use Logistiki.Event, type: "transfer_settled"

  defevent do
    field :cash_account_code, :string
    field :destination_account_code, :string
  end
end
