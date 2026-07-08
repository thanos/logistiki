defmodule Logistiki.Audit.AuditEvent do
  @moduledoc """
  A persisted audit event.

  Every important action in the accounting pipeline records an audit event so
  that, later, one can answer *why* a posting exists, which business event
  caused it, which rules fired, which policy was selected, which template was
  used, which accounts were selected, who initiated it, and how the balance was
  derived.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "audit_events" do
    field :actor_id, :string
    field :event_id, :string
    field :journal_id, :id
    field :action, :string
    field :resource_type, :string
    field :resource_id, :string
    field :before, :map
    field :after, :map
    field :explanation, :map
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
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
