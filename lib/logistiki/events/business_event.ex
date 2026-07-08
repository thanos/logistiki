defmodule Logistiki.Events.BusinessEvent do
  @moduledoc """
  Persisted record of a normalized business event.

  Business event persistence enables replay and audit. The `payload` stores the
  original event as published by the application; `normalized_payload` stores the
  flattened `Logistiki.Event.Normalized` representation used by the pipeline.

  ## Fields

    * `id` — `integer()` — primary key (e.g. `1`)
    * `event_type` — `String.t()` — e.g. `"deposit_received"`, `"fee_assessed"`
    * `source_system` — `String.t() | nil` — e.g. `"bank_core"`, `"onboarding"`
    * `source_id` — `String.t() | nil` — e.g. `"wire_123"`, `"crm_456"`
    * `actor_id` — `String.t() | nil` — who initiated the event (e.g. `"user_789"`)
    * `occurred_at` — `DateTime.t() | nil` — when the event happened (e.g. `~U[2026-07-07 12:00:00Z]`)
    * `effective_date` — `Date.t() | nil` — accounting effective date (e.g. `~D[2026-07-07]`)
    * `payload` — `map()` — the original event as a string-keyed map (default `%{}`)
    * `normalized_payload` — `map() | nil` — the `Normalized.to_map/1` representation
    * `status` — `String.t()` — one of `statuses/0` (default `"received"`, e.g. `"processed"`)
    * `explanation` — `map() | nil` — pipeline explanation (on completion)
    * `metadata` — `map()` — extensible metadata (default `%{}`)
    * `inserted_at` — `DateTime.t() | nil` — set by Ecto
    * `updated_at` — `DateTime.t() | nil` — set by Ecto

  ## Status transitions

  `received` → `normalized` → `processed` (or `no_accounting_impact`,
  `blocked`, `requires_approval`, `failed`).

  ## Example

      %Logistiki.Events.BusinessEvent{
        id: 1,
        event_type: "deposit_received",
        source_system: "bank_core",
        source_id: "wire_123",
        status: "processed",
        normalized_payload: %{"id" => "evt_001", "type" => "deposit_received", ...},
        inserted_at: ~U[2026-07-07 12:00:00Z]
      }
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(received normalized blocked requires_approval processed no_accounting_impact failed)a

  schema "business_events" do
    # Event type string. Example: `\"deposit_received\"`, `\"fee_assessed\"`
    field(:event_type, :string)
    # Source system that published the event. Example: `\"bank_core\"`, `\"onboarding\"`
    field(:source_system, :string)
    # Source-system event id. Example: `\"wire_123\"`, `\"crm_456\"`
    field(:source_id, :string)
    # Actor who initiated the event. Example: `\"user_789\"`
    field(:actor_id, :string)
    # When the event occurred. Example: `~U[2026-07-07 12:00:00Z]`
    field(:occurred_at, :utc_datetime)
    # Accounting effective date. Example: `~D[2026-07-07]`
    field(:effective_date, :date)
    # Original event as a string-keyed map. Default: `%{}`.
    field(:payload, :map, default: %{})
    # Normalized event representation (`Normalized.to_map/1`).
    field(:normalized_payload, :map)
    # Event status, one of `statuses/0`. Default: `\"received\"`. Example: `\"processed\"`
    field(:status, :string, default: "received")
    # Pipeline explanation map (set on completion). Example: `%{policy: :cash_deposit}`
    field(:explanation, :map)
    # Extensible metadata. Default: `%{}`.
    field(:metadata, :map, default: %{})

    timestamps(type: :utc_datetime)
  end

  @typedoc """
  The `BusinessEvent` struct type — a persisted record of a normalized business
  event.

  ## Fields

    * `id` — `integer() | nil` — primary key
    * `event_type` — `String.t() | nil` — e.g. `"deposit_received"`
    * `source_system` — `String.t() | nil` — e.g. `"bank_core"`
    * `source_id` — `String.t() | nil` — e.g. `"wire_123"`
    * `actor_id` — `String.t() | nil` — e.g. `"user_789"`
    * `occurred_at` — `DateTime.t() | nil` — e.g. `~U[2026-07-07 12:00:00Z]`
    * `effective_date` — `Date.t() | nil` — e.g. `~D[2026-07-07]`
    * `payload` — `map() | nil` — original event as a string-keyed map
    * `normalized_payload` — `map() | nil` — flattened event representation
    * `status` — `String.t() | nil` — e.g. `"processed"`, `"blocked"`
    * `explanation` — `map() | nil` — pipeline explanation
    * `metadata` — `map() | nil` — extensible metadata
    * `inserted_at` — `DateTime.t() | nil`
    * `updated_at` — `DateTime.t() | nil`

  ## Example

      %Logistiki.Events.BusinessEvent{
        id: 1, event_type: "deposit_received", status: "processed"
      }
  """
  @type t :: %__MODULE__{
          id: integer() | nil,
          event_type: String.t() | nil,
          source_system: String.t() | nil,
          source_id: String.t() | nil,
          actor_id: String.t() | nil,
          occurred_at: DateTime.t() | nil,
          effective_date: Date.t() | nil,
          payload: map() | nil,
          normalized_payload: map() | nil,
          status: String.t() | nil,
          explanation: map() | nil,
          metadata: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Returns the list of allowed business-event statuses as atoms.

  ## Returns

    * `[atom()]` — `[:received, :normalized, :blocked, :requires_approval,
      :processed, :no_accounting_impact, :failed]`

  ## Examples

      iex> :processed in Logistiki.Events.BusinessEvent.statuses()
      true
  """
  @doc since: "0.1.0"
  @spec statuses() :: [atom(), ...]
  def statuses, do: @statuses

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :event_type,
      :source_system,
      :source_id,
      :actor_id,
      :occurred_at,
      :effective_date,
      :payload,
      :normalized_payload,
      :status,
      :explanation,
      :metadata
    ])
    |> validate_required([:event_type, :status])
    |> validate_inclusion(:status, Enum.map(@statuses, &Atom.to_string/1))
  end
end
