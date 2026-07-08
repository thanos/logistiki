defmodule Logistiki.Event.DepositReceived do
  @moduledoc """
  A cash or wire deposit received into a client account.

  Accounting impact: debit cash (nostro), credit client liability.
  """

  use Logistiki.Event, type: "deposit_received"

  defevent do
    field :cash_account_code, :string
  end
end
