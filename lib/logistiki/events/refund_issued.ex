defmodule Logistiki.Event.RefundIssued do
  @moduledoc """
  A refund issued to a customer. Accounting impact mirrors a withdrawal.
  """

  use Logistiki.Event, type: "refund_issued"

  defevent do
    field :cash_account_code, :string
  end
end
