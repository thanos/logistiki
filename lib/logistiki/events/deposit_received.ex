defmodule Logistiki.Event.DepositReceived do
  @moduledoc """
  A cash or wire deposit received into a client account.

  Accounting impact: debit cash (nostro), credit client liability.

  ## Fields

  Inherits all common fields from `Logistiki.Event` plus:

    * `cash_account_code` — `String.t() | nil` — the nostro/cash account code
      (e.g. `"ASSETS:CASH:USD:NOSTRO"`)

  ## Example

      %Logistiki.Event.DepositReceived{
        id: "evt_001",
        entity_type: "corporate",
        account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
        cash_account_code: "ASSETS:CASH:USD:NOSTRO",
        amount: Decimal.new("1000.00"),
        currency: "USD",
        occurred_at: ~U[2026-07-07 12:00:00Z],
        effective_date: ~D[2026-07-07],
        source_system: "bank_core",
        source_id: "wire_123"
      }
  """

  use Logistiki.Event, type: "deposit_received"

  defevent do
    field :cash_account_code, :string
  end
end
