defmodule Logistiki.Events.BusinessEvent do
  @moduledoc """
  Persisted record of a normalized business event.

  Business event persistence enables replay and audit. The `payload` stores the
  original event as published by the application; `normalized_payload` stores the
  flattened `Logistiki.Event.Normalized` representation used by the pipeline.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(received normalized blocked requires_approval processed no_accounting_impact failed)a

  schema "business_events" do
    field :event_type, :string
    field :source_system, :string
    field :source_id, :string
    field :actor_id, :string
    field :occurred_at, :utc_datetime
    field :effective_date, :date
    field :payload, :map, default: %{}
    field :normalized_payload, :map
    field :status, :string, default: "received"
    field :explanation, :map
    field :metadata, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc false
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
