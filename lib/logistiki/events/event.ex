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
  """
  defmacro defevent(do: block) do
    quote do
      @primary_key false
      embedded_schema do
        field :id, :string
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
        field :counterparty_id, :string
        field :product_code, :string
        field :jurisdiction, :string
        field :entity_type, :string
        field :metadata, :map, default: %{}

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

  @doc "Returns the string event type used by the knowledge layer."
  @callback event_type(struct :: term()) :: String.t()

  @doc "Normalizes the event into a `Logistiki.Event.Normalized` struct."
  @callback normalize(struct :: term()) :: {:ok, Logistiki.Event.Normalized.t()} | {:error, term()}

  @doc "Dispatches to the event struct's `event_type/1` implementation."
  def event_type(%module{} = event), do: module.event_type(event)

  @doc "Dispatches to the event struct's `normalize/1` implementation."
  def normalize(%module{} = event), do: module.normalize(event)
end
