defmodule Logistiki.Event.AccountOpened do
  @moduledoc """
  A customer account was opened. This event has **no accounting impact**: it
  produces audit evidence only.

  `has_accounting_impact` defaults to `false`. When processed, the pipeline
  returns a `%Logistiki.Accounting.Result{journal: nil}` with an explanation
  of `%{reason: :no_accounting_impact}`.

  ## Fields

  Inherits all common fields from `Logistiki.Event` plus:

    * `has_accounting_impact` — `boolean()` — default `false`

  ## Example

      %Logistiki.Event.AccountOpened{
        id: "evt_007",
        account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
        effective_date: ~D[2026-07-07],
        source_system: "onboarding"
      }

      iex> {:ok, result} = Logistiki.process(%Logistiki.Event.AccountOpened{id: "evt_007"})
      iex> result.journal
      nil
      iex> result.explanation[:reason]
      :no_accounting_impact
  """

  use Logistiki.Event, type: "account_opened"

  defevent do
    field :has_accounting_impact, :boolean, default: false
  end
end
