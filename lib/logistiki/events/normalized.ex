defmodule Logistiki.Event.Normalized do
  @moduledoc """
  The canonical, flattened representation of a business event.

  The knowledge layer generates facts from this struct. Not every event
  populates every field.

  ## Fields

    * `id` — `String.t() | nil` — the event id (e.g. `"evt_001"`)
    * `type` — `String.t()` — the event type (e.g. `"deposit_received"`)
    * `source_system` — `String.t() | nil` — e.g. `"bank_core"`
    * `source_id` — `String.t() | nil` — e.g. `"wire_123"`
    * `actor_id` — `String.t() | nil`
    * `occurred_at` — `DateTime.t() | nil`
    * `effective_date` — `Date.t() | nil`
    * `amount` — `Decimal.t() | nil` — e.g. `Decimal.new("1000.00")`
    * `currency` — `String.t() | nil` — e.g. `"USD"`
    * `entity_id` — `String.t() | nil`
    * `account_id` — `String.t() | nil`
    * `account_code` — `String.t() | nil` — e.g. `"LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING"`
    * `cash_account_code` — `String.t() | nil`
    * `fee_income_account_code` — `String.t() | nil`
    * `interest_expense_account_code` — `String.t() | nil`
    * `destination_account_code` — `String.t() | nil`
    * `counterparty_account_code` — `String.t() | nil`
    * `counterparty_id` — `String.t() | nil`
    * `product_code` — `String.t() | nil`
    * `jurisdiction` — `String.t() | nil`
    * `fee_type` — `String.t() | nil` — e.g. `"wire_fee"`
    * `entity_type` — `String.t() | nil` — e.g. `"corporate"`, `"individual"`
    * `has_accounting_impact` — `boolean()` — default `true`; `false` for
      events like `AccountOpened`
    * `metadata` — `map()` — default `%{}`

  ## Example

      %Logistiki.Event.Normalized{
        id: "evt_001",
        type: "deposit_received",
        amount: Decimal.new("1000.00"),
        currency: "USD",
        account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
        cash_account_code: "ASSETS:CASH:USD:NOSTRO",
        entity_type: "corporate",
        effective_date: ~D[2026-07-07]
      }
  """

  use Ecto.Schema

  @typedoc """
  The canonical, flattened representation of a business event.

  The knowledge layer generates facts from this struct. Not every event
  populates every field.

  ## Fields

    * `id` — `String.t() | nil` — event id (e.g. `"evt_001"`)
    * `type` — `String.t()` — event type (e.g. `"deposit_received"`, `"fee_assessed"`)
    * `source_system` — `String.t() | nil` — e.g. `"bank_core"`, `"onboarding"`
    * `source_id` — `String.t() | nil` — e.g. `"wire_123"`
    * `actor_id` — `String.t() | nil` — e.g. `"user_789"`
    * `occurred_at` — `DateTime.t() | nil` — e.g. `~U[2026-07-07 12:00:00Z]`
    * `effective_date` — `Date.t() | nil` — e.g. `~D[2026-07-07]`
    * `amount` — `Decimal.t() | nil` — e.g. `Decimal.new("1000.00")`
    * `currency` — `String.t() | nil` — e.g. `"USD"`, `"EUR"`
    * `entity_id` — `String.t() | nil` — e.g. `"1"`
    * `account_id` — `String.t() | nil` — e.g. `"10"`
    * `account_code` — `String.t() | nil` — e.g. `"LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING"`
    * `cash_account_code` — `String.t() | nil` — e.g. `"ASSETS:CASH:USD:NOSTRO"`
    * `fee_income_account_code` — `String.t() | nil` — e.g. `"INCOME:FEES:WIRE"`
    * `interest_expense_account_code` — `String.t() | nil` — e.g. `"EXPENSES:INTEREST"`
    * `destination_account_code` — `String.t() | nil` — e.g. `"LIABILITIES:CLIENT_DEPOSITS:USD:ACME:PAYROLL"`
    * `counterparty_account_code` — `String.t() | nil` — e.g. `"LIABILITIES:CLIENT_DEPOSITS:USD:VENDOR"`
    * `counterparty_id` — `String.t() | nil` — e.g. `"5"`
    * `product_code` — `String.t() | nil` — e.g. `"retail_deposit"`
    * `jurisdiction` — `String.t() | nil` — e.g. `"US"`, `"EU"`
    * `fee_type` — `String.t() | nil` — e.g. `"wire_fee"`, `"monthly_fee"`
    * `entity_type` — `String.t() | nil` — e.g. `"corporate"`, `"individual"`
    * `has_accounting_impact` — `boolean()` — default `true`; `false` for `AccountOpened`
    * `metadata` — `map()` — default `%{}`

  ## Example

      %Logistiki.Event.Normalized{
        id: "evt_001", type: "deposit_received",
        amount: Decimal.new("1000.00"), currency: "USD",
        account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
        cash_account_code: "ASSETS:CASH:USD:NOSTRO",
        entity_type: "corporate", effective_date: ~D[2026-07-07]
      }
  """
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

  @doc """
  Builds a normalized event from a keyword/map of fields.

  ## Arguments

    * `attrs` — `keyword()` or `map()` of field names to values.

  ## Returns

    * `%Logistiki.Event.Normalized{}` — the struct.

  ## Examples

      iex> Logistiki.Event.Normalized.new(%{id: "evt_1", type: "deposit_received", amount: Decimal.new("100")})
      %Logistiki.Event.Normalized{id: "evt_1", type: "deposit_received", amount: Decimal.new("100"), ...}
  """
  @doc since: "0.1.0"
  @spec new(keyword() | map()) :: t()
  def new(attrs) do
    struct(__MODULE__, Map.new(attrs))
  end

  @doc """
  Converts the normalized event into a plain string-keyed map suitable for
  persistence (JSONB columns) and audit records.

  `Decimal` → string, `DateTime` → ISO 8601, `Date` → ISO 8601. Nil fields are
  omitted.

  ## Arguments

    * `event` — `%Logistiki.Event.Normalized{}`.

  ## Returns

    * `map()` — string-keyed, with encoded values.

  ## Examples

      iex> Logistiki.Event.Normalized.to_map(%Logistiki.Event.Normalized{id: "evt_1", type: "deposit_received", amount: Decimal.new("1000.00")})
      %{"id" => "evt_1", "type" => "deposit_received", "amount" => "1000.00", "has_accounting_impact" => true, "metadata" => %{}}
  """
  @doc since: "0.1.0"
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    event
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{}, fn {k, v} -> {Atom.to_string(k), encode_value(v)} end)
  end

  # Encodes a value for JSON-safe persistence.
  defp encode_value(%Decimal{} = d), do: Decimal.to_string(d)
  defp encode_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp encode_value(%Date{} = d), do: Date.to_iso8601(d)
  defp encode_value(v) when is_map(v), do: encode_map(v)
  defp encode_value(v) when is_list(v), do: Enum.map(v, &encode_value/1)
  defp encode_value(v), do: v

  # Recursively encodes a map's values, converting atom keys to strings.
  defp encode_map(map) do
    Enum.into(map, %{}, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), encode_value(v)}
      {k, v} -> {k, encode_value(v)}
    end)
  end
end
