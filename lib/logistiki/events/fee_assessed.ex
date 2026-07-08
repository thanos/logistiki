defmodule Logistiki.Event.FeeAssessed do
  @moduledoc """
  A fee assessed against a client account (e.g. a wire fee).

  Accounting impact: debit client liability, credit fee income.
  """

  use Logistiki.Event, type: "fee_assessed"

  defevent do
    field :fee_income_account_code, :string
    field :fee_type, :string
  end
end
