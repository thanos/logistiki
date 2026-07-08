defmodule Logistiki.Event.Normalized do
  @moduledoc """
  The canonical, flattened representation of a business event.

  The knowledge layer generates facts from this struct. Not every event
  populates every field.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: String.t() | nil,
          type: String.t(),
          source_system: String.t() | nil,
          source_id: String.t() | nil,
          actor_id: String.t() | nil,
          occurred_at: DateTime.t() | nil,
          effective_date: Date.t() | nil,
          amount: Decimal.t() | nil,
          currency: String.t() | nil,
          entity_id: String.t() | nil,
          account_id: String.t() | nil,
          account_code: String.t() | nil,
          cash_account_code: String.t() | nil,
          fee_income_account_code: String.t() | nil,
          interest_expense_account_code: String.t() | nil,
          destination_account_code: String.t() | nil,
          counterparty_account_code: String.t() | nil,
          counterparty_id: String.t() | nil,
          product_code: String.t() | nil,
          jurisdiction: String.t() | nil,
          fee_type: String.t() | nil,
          entity_type: String.t() | nil,
          has_accounting_impact: boolean(),
          metadata: map()
        }

  @primary_key false
  embedded_schema do
    field :id, :string
    field :type, :string
    field :source_system, :string
    field :source_id, :string
    field :actor_id, :string
    field :occurred_at, :utc_datetime
    field :effective_date, :date
    field :amount, :decimal
    field :currency, :string
    field :entity_id, :string
    field :account_id, :string
    field :account_code, :string
    field :cash_account_code, :string
    field :fee_income_account_code, :string
    field :interest_expense_account_code, :string
    field :destination_account_code, :string
    field :counterparty_account_code, :string
    field :counterparty_id, :string
    field :product_code, :string
    field :jurisdiction, :string
    field :fee_type, :string
    field :entity_type, :string
    field :has_accounting_impact, :boolean, default: true
    field :metadata, :map, default: %{}
  end

  @doc "Builds a normalized event from a keyword/map of fields."
  def new(attrs) do
    struct(__MODULE__, Map.new(attrs))
  end

  @doc "Converts the normalized event into a plain string-keyed map (for persistence/audit)."
  def to_map(%__MODULE__{} = event) do
    event
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{}, fn {k, v} -> {Atom.to_string(k), encode_value(v)} end)
  end

  defp encode_value(%Decimal{} = d), do: Decimal.to_string(d)
  defp encode_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp encode_value(%Date{} = d), do: Date.to_iso8601(d)
  defp encode_value(v) when is_map(v), do: encode_map(v)
  defp encode_value(v) when is_list(v), do: Enum.map(v, &encode_value/1)
  defp encode_value(v), do: v

  defp encode_map(map) do
    Enum.into(map, %{}, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), encode_value(v)}
      {k, v} -> {k, encode_value(v)}
    end)
  end
end
