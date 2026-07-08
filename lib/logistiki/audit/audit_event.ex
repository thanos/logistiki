defmodule Logistiki.Audit.AuditEvent do
  @moduledoc """
  A persisted audit event.

  Every important action in the accounting pipeline records an audit event so
  that, later, one can answer *why* a posting exists, which business event
  caused it, which rules fired, which policy was selected, which template was
  used, which accounts were selected, who initiated it, and how the balance was
  derived.

  ## Fields

    * `id` — `integer()` — primary key (e.g. `1`)
    * `actor_id` — `String.t() | nil` — who initiated the action (e.g. `"user_789"`)
    * `event_id` — `String.t() | nil` — the originating business event id (e.g. `"evt_001"`)
    * `journal_id` — `integer() | nil` — the related journal id (e.g. `5`)
    * `action` — `String.t()` — the pipeline stage action (e.g. `"journal_posted"`, `"business_event_received"`)
    * `resource_type` — `String.t() | nil` — the type of resource (e.g. `"journal"`, `"event"`)
    * `resource_id` — `String.t() | nil` — the resource id (e.g. `"1"`)
    * `before` — `map() | nil` — state before the action (for updates)
    * `after` — `map() | nil` — state after the action (for updates)
    * `explanation` — `map() | nil` — structured explanation (e.g. `%{policy: :cash_deposit}`)
    * `metadata` — `map()` — extensible metadata (default `%{}`)
    * `inserted_at` — `DateTime.t() | nil` — set on insert (no `updated_at`; e.g. `~U[2026-07-07 12:00:00Z]`)

  ## Captured actions

  `business_event_received`, `event_normalized`, `facts_generated`,
  `business_rules_evaluated`, `no_accounting_impact`, `policy_selected`,
  `template_selected`, `journal_built`, `invariant_validation_succeeded`,
  `invariant_validation_failed`, `journal_posted`, `journal_reversed`,
  `projection_generated`, `audit_event_written`.

  ## Example

      %Logistiki.Audit.AuditEvent{
        id: 1,
        event_id: "evt_001",
        journal_id: 5,
        action: "journal_posted",
        resource_type: "journal",
        resource_id: "5",
        explanation: %{policy: :cash_deposit, backend: Logistiki.Ledger.Simulation},
        inserted_at: ~U[2026-07-07 12:00:00Z]
      }
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "audit_events" do
    # Actor who initiated the action. Example: `\"user_789\"`
    field(:actor_id, :string)
    # Originating business event id. Example: `\"evt_001\"`
    field(:event_id, :string)
    # Related journal id. Example: `5`
    field(:journal_id, :id)
    # Pipeline stage action (required). Example: `\"journal_posted\"`, `\"business_event_received\"`
    field(:action, :string)
    # Type of resource acted upon. Example: `\"journal\"`, `\"event\"`
    field(:resource_type, :string)
    # Resource id. Example: `\"5\"`
    field(:resource_id, :string)
    # State before the action (for updates). Example: `%{status: \"draft\"}`
    field(:before, :map)
    # State after the action (for updates). Example: `%{status: \"posted\"}`
    field(:after, :map)
    # Structured explanation. Example: `%{policy: :cash_deposit}`
    field(:explanation, :map)
    # Extensible metadata. Default: `%{}`.
    field(:metadata, :map, default: %{})

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @typedoc """
  The `AuditEvent` struct type — a persisted record of a pipeline stage.

  ## Fields

    * `id` — `integer() | nil` — primary key
    * `actor_id` — `String.t() | nil` — e.g. `"user_789"`
    * `event_id` — `String.t() | nil` — originating event id (e.g. `"evt_001"`)
    * `journal_id` — `integer() | nil` — related journal id
    * `action` — `String.t() | nil` — e.g. `"journal_posted"`
    * `resource_type` — `String.t() | nil` — e.g. `"journal"`, `"event"`
    * `resource_id` — `String.t() | nil` — e.g. `"5"`
    * `before` — `map() | nil` — state before the action
    * `after` — `map() | nil` — state after the action
    * `explanation` — `map() | nil` — structured explanation
    * `metadata` — `map() | nil` — extensible metadata
    * `inserted_at` — `DateTime.t() | nil` — set on insert (no `updated_at`)

  ## Example

      %Logistiki.Audit.AuditEvent{
        id: 1, event_id: "evt_001", action: "journal_posted",
        explanation: %{policy: :cash_deposit}
      }
  """
  @type t :: %__MODULE__{
          id: integer() | nil,
          actor_id: String.t() | nil,
          event_id: String.t() | nil,
          journal_id: integer() | nil,
          action: String.t() | nil,
          resource_type: String.t() | nil,
          resource_id: String.t() | nil,
          before: map() | nil,
          after: map() | nil,
          explanation: map() | nil,
          metadata: map() | nil,
          inserted_at: DateTime.t() | nil
        }

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(audit_event, attrs) do
    audit_event
    |> cast(attrs, [
      :actor_id,
      :event_id,
      :journal_id,
      :action,
      :resource_type,
      :resource_id,
      :before,
      :after,
      :explanation,
      :metadata
    ])
    |> validate_required([:action])
  end
end
