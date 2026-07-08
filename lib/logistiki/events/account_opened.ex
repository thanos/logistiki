defmodule Logistiki.Event.AccountOpened do
  @moduledoc """
  A customer account was opened. This event has **no accounting impact**: it
  produces audit evidence only.
  """

  use Logistiki.Event, type: "account_opened"

  defevent do
    field :has_accounting_impact, :boolean, default: false
  end
end
