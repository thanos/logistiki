defmodule Logistiki.Knowledge.Facts do
  @moduledoc """
  Generates runtime Datalog facts from a normalized business event.

  The event is represented in the Datalog program by the fixed atom `:evt`.
  Generated facts are added to a blank `Logistiki.Knowledge.Program` before
  materialization.
  """

  alias Logistiki.Event.Normalized

  @event_id :evt

  @doc "The fixed event identifier used inside the Datalog program."
  def event_id, do: @event_id

  @doc "Generates a list of `{relation, values}` facts for `normalized`."
  def generate(%Normalized{} = event) do
    []
    |> add(:event_type, [@event_id, to_atom(event.type)])
    |> add_if(:event_currency, [@event_id, event.currency], event.currency)
    |> add_if(:event_amount_cents, [@event_id, amount_cents(event.amount)], event.amount)
    |> add_if(:event_fee_type, [@event_id, to_atom(event.fee_type)], event.fee_type)
    |> add_if(:event_entity_type, [@event_id, to_atom(event.entity_type)], event.entity_type)
    |> add_if(:event_product, [@event_id, to_atom(event.product_code)], event.product_code)
    |> add_if(:event_account, [@event_id, event.account_code], event.account_code)
    |> add_if(:event_cash_account, [@event_id, event.cash_account_code], event.cash_account_code)
    |> add_if(:event_fee_income_account, [@event_id, event.fee_income_account_code], event.fee_income_account_code)
    |> add_if(:event_interest_expense_account, [@event_id, event.interest_expense_account_code], event.interest_expense_account_code)
    |> add_if(:event_destination_account, [@event_id, event.destination_account_code], event.destination_account_code)
  end

  defp add(facts, relation, values), do: facts ++ [{relation, values}]

  defp add_if(facts, _relation, _values, nil), do: facts
  defp add_if(facts, relation, values, _value), do: add(facts, relation, values)

  defp to_atom(nil), do: nil
  defp to_atom(value) when is_atom(value), do: value
  defp to_atom(value) when is_binary(value), do: String.to_atom(value)

  defp amount_cents(nil), do: nil

  defp amount_cents(%Decimal{} = amount) do
    amount
    |> Decimal.mult(100)
    |> Decimal.round(0, :down)
    |> Decimal.to_integer()
  end
end
