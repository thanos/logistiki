defmodule Logistiki.Knowledge.Facts do
  @moduledoc """
  Generates runtime Datalog facts from a normalized business event.

  The event is represented in the Datalog program by the fixed atom `:evt`.
  Generated facts are added to the program before materialization.

  ## Generated relations

  | Relation | Arity | Example |
  |----------|-------|---------|
  | `event_type` | 2 | `{:evt, :deposit_received}` |
  | `event_currency` | 2 | `{:evt, "USD"}` |
  | `event_amount_cents` | 2 | `{:evt, 100000}` |
  | `event_fee_type` | 2 | `{:evt, :wire_fee}` |
  | `event_entity_type` | 2 | `{:evt, :corporate}` |
  | `event_product` | 2 | `{:evt, :retail_deposit}` |
  | `event_account` | 2 | `{:evt, "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING"}` |
  | `event_cash_account` | 2 | `{:evt, "ASSETS:CASH:USD:NOSTRO"}` |
  | `event_fee_income_account` | 2 | `{:evt, "INCOME:FEES:WIRE"}` |
  | `event_interest_expense_account` | 2 | `{:evt, "EXPENSES:INTEREST"}` |
  | `event_destination_account` | 2 | `{:evt, "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:PAYROLL"}` |

  Only fields with non-nil values generate facts.
  """

  alias Logistiki.Event.Normalized

  @event_id :evt

  @doc """
  Returns the fixed event identifier used inside the Datalog program.

  ## Returns

    * `:evt` — the atom representing the current event in all Datalog rules.

  ## Examples

      iex> Logistiki.Knowledge.Facts.event_id()
      :evt
  """
  @doc since: "0.1.0"
  @spec event_id() :: :evt
  def event_id, do: @event_id

  @doc """
  Generates a list of `{relation, values}` facts for `normalized`.

  ## Arguments

    * `normalized` — `%Logistiki.Event.Normalized{}` — the flattened event.

  ## Returns

    * `[{atom(), [term()]}]` — a list of `{relation_name, argument_list}`
      tuples ready to be added to the Datalog program.

  ## Examples

      iex> facts = Logistiki.Knowledge.Facts.generate(%Logistiki.Event.Normalized{
      ...>   type: "deposit_received", amount: Decimal.new("1000.00"), currency: "USD",
      ...>   account_code: "LIAB:ACME", cash_account_code: "ASSETS:CASH"
      ...> })
      iex> {:event_type, [:evt, :deposit_received]} in facts
      true
      iex> {:event_currency, [:evt, "USD"]} in facts
      true
      iex> {:event_amount_cents, [:evt, 100000]} in facts
      true
  """
  @doc since: "0.1.0"
  @spec generate(Normalized.t()) :: [{atom(), [term()]}]
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

  # Appends a fact to the list.
  defp add(facts, relation, values), do: facts ++ [{relation, values}]

  # Appends a fact only when `value` is not nil.
  defp add_if(facts, _relation, _values, nil), do: facts
  defp add_if(facts, relation, values, _value), do: add(facts, relation, values)

  # Converts a binary or atom to an atom (for Datalog constants).
  defp to_atom(nil), do: nil
  defp to_atom(value) when is_atom(value), do: value
  defp to_atom(value) when is_binary(value), do: String.to_atom(value)

  # Converts a Decimal amount to integer cents (rounded down). Used for
  # comparison constraints in Datalog (e.g. `gt(Amount, 1_000_000)`).
  defp amount_cents(nil), do: nil

  defp amount_cents(%Decimal{} = amount) do
    amount
    |> Decimal.mult(100)
    |> Decimal.round(0, :down)
    |> Decimal.to_integer()
  end
end
