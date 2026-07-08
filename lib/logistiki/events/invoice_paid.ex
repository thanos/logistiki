defmodule Logistiki.Event.InvoicePaid do
  @moduledoc """
  An invoice paid by a customer from their operating account.
  """

  use Logistiki.Event, type: "invoice_paid"

  defevent do
    field :cash_account_code, :string
    field :counterparty_account_code, :string
  end
end
