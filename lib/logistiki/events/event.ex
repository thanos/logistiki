defmodule Logistiki.Event do
  @moduledoc """
  Behaviour implemented by business events.

  Applications publish business events. Logistiki decides whether and how those
  events become accounting entries. An event must be able to report its type and
  normalize itself into a `Logistiki.Event.Normalized` struct.

  ## Defining events

  Use the `defevent` macro to declare a business event struct with the common
  normalized fields and an automatic `Logistiki.Event` implementation:

      defmodule Logistiki.Event.DepositReceived do
        use Logistiki.Event, type: "deposit_received"

        defevent do
          field :cash_account_code, :string
        end
      end

  ## Common fields provided by `defevent`

  Every event struct built with `defevent` includes: `id`, `source_system`,
  `source_id`, `actor_id`, `occurred_at`, `effective_date`, `amount`,
  `currency`, `entity_id`, `account_id`, `account_code`, `counterparty_id`,
  `product_code`, `jurisdiction`, `entity_type`, `metadata`. Additional
  event-specific fields are declared inside the `defevent do ... end` block.

  ## Dispatchers

  `Logistiki.Event.event_type/1` and `Logistiki.Event.normalize/1` dispatch to
  the event struct's implementation so callers don't need to know the module.
  """

  @doc """
  Injects the `Logistiki.Event` behaviour and the `event_type/1` implementation
  into the calling module. Used with `use Logistiki.Event, type: "..."`.

  ## Options

    * `:type` — `String.t` — the event type string used by the knowledge layer
      (e.g. `"deposit_received"`, `"fee_assessed"`).

  ## Example

      use Logistiki.Event, type: "deposit_received"
  """
  defmacro __using__(opts) do
    quote do
      use Ecto.Schema
      @behaviour Logistiki.Event

      import Logistiki.Event, only: [defevent: 1]

      @event_type unquote(opts[:type])

      @impl true
      def event_type(_), do: @event_type
    end
  end

  @doc """
  Declares the event struct fields (beyond the common normalized fields) and
  generates a `normalize/1` implementation that flattens the event into a
  `Logistiki.Event.Normalized` struct.

  ## Arguments

    * `block` — a `do` block containing `Ecto.Schema.field/3` declarations for
      event-specific fields (e.g. `field :cash_account_code, :string`).

  ## Generated code

  The macro builds an `embedded_schema` with the common fields plus any
  declared fields, and a `normalize/1` function that constructs a
  `%Logistiki.Event.Normalized{}` from the event struct, merging in any
  extra event-specific fields (like `cash_account_code`).

  ## Example

      defevent do
        field :cash_account_code, :string
        field :fee_income_account_code, :string
      end
  """
  @doc since: "0.1.0"
  defmacro defevent(do: block) do
    quote do
      @primary_key false
      embedded_schema do
        field(:id, :string)
        field(:source_system, :string)
        field(:source_id, :string)
        field(:actor_id, :string)
        field(:occurred_at, :utc_datetime)
        field(:effective_date, :date)
        field(:amount, :decimal)
        field(:currency, :string)
        field(:entity_id, :string)
        field(:account_id, :string)
        field(:account_code, :string)
        field(:counterparty_id, :string)
        field(:product_code, :string)
        field(:jurisdiction, :string)
        field(:entity_type, :string)
        field(:metadata, :map, default: %{})

        unquote(block)
      end

      @impl true
      def normalize(%__MODULE__{} = event) do
        normalized =
          Logistiki.Event.Normalized.new(%{
            id: event.id,
            type: event_type(event),
            source_system: event.source_system,
            source_id: event.source_id,
            actor_id: event.actor_id,
            occurred_at: event.occurred_at,
            effective_date: event.effective_date,
            amount: event.amount,
            currency: event.currency,
            entity_id: event.entity_id,
            account_id: event.account_id,
            account_code: event.account_code,
            counterparty_id: event.counterparty_id,
            product_code: event.product_code,
            jurisdiction: event.jurisdiction,
            entity_type: event.entity_type,
            has_accounting_impact: Map.get(event, :has_accounting_impact, true),
            metadata: event.metadata
          })
          |> merge_extra_fields(event)

        {:ok, normalized}
      end

      # Merges event-specific fields (e.g. `cash_account_code`) that aren't in
      # the common set into the Normalized struct, when they have a non-nil
      # value.
      defp merge_extra_fields(normalized, event) do
        event
        |> Map.from_struct()
        |> Enum.reduce(normalized, fn {k, v}, acc ->
          case Map.get(acc, k) do
            nil when not is_nil(v) -> Map.put(acc, k, v)
            _ -> acc
          end
        end)
      end
    end
  end

  @doc """
  Returns the string event type used by the knowledge layer.

  ## Callback arguments

    * `struct` — the event struct (e.g. `%Logistiki.Event.DepositReceived{}`).

  ## Returns

    * `String.t()` — e.g. `"deposit_received"`.
  """
  @callback event_type(struct :: term()) :: String.t()

  @doc """
  Normalizes the event into a `Logistiki.Event.Normalized` struct.

  ## Callback arguments

    * `struct` — the event struct.

  ## Returns

    * `{:ok, %Logistiki.Event.Normalized{}}` — the flattened event.
    * `{:error, term()}` — normalization failed.
  """
  @callback normalize(struct :: term()) :: {:ok, Logistiki.Event.Normalized.t()} | {:error, term()}

  @doc """
  Dispatches to the event struct's `event_type/1` implementation.

  ## Arguments

    * `event` — a struct implementing `Logistiki.Event`.

  ## Returns

    * `String.t()` — the event type (e.g. `"deposit_received"`).

  ## Examples

      iex> Logistiki.Event.event_type(%Logistiki.Event.DepositReceived{})
      "deposit_received"
  """
  @doc since: "0.1.0"
  @spec event_type(struct()) :: String.t()
  def event_type(%module{} = event), do: module.event_type(event)

  @doc """
  Dispatches to the event struct's `normalize/1` implementation.

  ## Arguments

    * `event` — a struct implementing `Logistiki.Event`.

  ## Returns

    * `{:ok, %Logistiki.Event.Normalized{}}` — the flattened event.
    * `{:error, term()}` — normalization failed.

  ## Examples

      iex> {:ok, normalized} = Logistiki.Event.normalize(%Logistiki.Event.DepositReceived{id: "evt_1"})
      iex> normalized.type
      "deposit_received"
  """
  @doc since: "0.1.0"
  @spec normalize(struct()) :: {:ok, Logistiki.Event.Normalized.t()} | {:error, term()}
  def normalize(%module{} = event), do: module.normalize(event)
end
