defmodule Logistiki.Audit.AuditPending do
  @moduledoc """
  Durable pending enriched audit stages that may be drained asynchronously.

  Mandatory commit provenance is written synchronously inside the accounting
  Multi. Stage-level enrichment lands here so failure to drain never undoes a
  committed posting.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending drained failed)a

  schema "audit_pending" do
    field(:event_id, :string)
    field(:journal_id, :integer)
    field(:action, :string)
    field(:resource_type, :string)
    field(:resource_id, :string)
    field(:explanation, :map)
    field(:metadata, :map, default: %{})
    field(:status, :string, default: "pending")
    field(:attempts, :integer, default: 0)
    field(:last_error, :string)

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @doc false
  def changeset(pending, attrs) do
    pending
    |> cast(attrs, [
      :event_id,
      :journal_id,
      :action,
      :resource_type,
      :resource_id,
      :explanation,
      :metadata,
      :status,
      :attempts,
      :last_error
    ])
    |> validate_required([:action, :status])
    |> validate_inclusion(:status, Enum.map(@statuses, &Atom.to_string/1))
  end

  @doc false
  def statuses, do: @statuses
end
