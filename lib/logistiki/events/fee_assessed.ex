defmodule Logistiki.Event.FeeAssessed do
  @moduledoc """
  A fee assessed against a client account (e.g. a wire fee).

  Accounting impact: debit client liability, credit fee income.

  ## Fields

  Inherits all common fields from `Logistiki.Event` plus:

    * `fee_income_account_code` — `String.t() | nil` — the fee income account
      code (e.g. `"INCOME:FEES:WIRE"`)
    * `fee_type` — `String.t() | nil` — the fee type used by the knowledge layer
      to select a policy (e.g. `"wire_fee"`)

  ## Example

      %Logistiki.Event.FeeAssessed{
        id: "evt_003",
        entity_type: "corporate",
        account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
        fee_income_account_code: "INCOME:FEES:WIRE",
        amount: Decimal.new("25.00"),
        currency: "USD",
        fee_type: "wire_fee",
        effective_date: ~D[2026-07-07]
      }
  """

  use Logistiki.Event, type: "fee_assessed"

  defevent do
    field(:fee_income_account_code, :string)
    field(:fee_type, :string)
  end
end
