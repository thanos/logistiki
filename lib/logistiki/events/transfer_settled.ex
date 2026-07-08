defmodule Logistiki.Event.TransferSettled do
  @moduledoc """
  An internal transfer settled between two accounts (e.g. operating -> payroll).
  """

  use Logistiki.Event, type: "transfer_settled"

  defevent do
    field :cash_account_code, :string
    field :destination_account_code, :string
  end
end
