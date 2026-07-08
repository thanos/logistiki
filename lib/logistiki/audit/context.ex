defmodule Logistiki.Audit do
  @moduledoc """
  The context for audit evidence.

  Every important action in the accounting pipeline records an audit event so
  that the full chain — business event, rules, policy, template, journal,
  postings, ledger result — can be explained later.
  """

  import Ecto.Query

  alias Logistiki.Audit.AuditEvent
  alias Logistiki.Audit.Evidence
  alias Logistiki.Repo

  @doc "Records a single audit event."
  def record(attrs) do
    %AuditEvent{}
    |> AuditEvent.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Records every stage in an `Evidence` struct as an audit event."
  def record_evidence(%Evidence{stages: stages, event_id: event_id, journal_id: journal_id}) do
    Enum.each(stages, fn stage ->
      record(%{
        event_id: to_string(event_id),
        journal_id: journal_id,
        action: to_string(stage.action),
        resource_type: stage[:resource_type] && to_string(stage[:resource_type]),
        resource_id: stage[:resource_id] && to_string(stage[:resource_id]),
        explanation: stage[:explanation],
        metadata: Map.get(stage, :metadata, %{})
      })
    end)

    :ok
  end

  @doc "Lists audit events, optionally filtered by `:event_id`, `:journal_id`, or `:action`."
  def list_audit_events(opts \\ []) do
    AuditEvent
    |> maybe_filter(:event_id, opts)
    |> maybe_filter(:journal_id, opts)
    |> maybe_filter(:action, opts)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  @doc "Returns the full audit trail for a business event."
  def trail_for_event(event_id) do
    Repo.all(
      from a in AuditEvent,
        where: a.event_id == ^to_string(event_id),
        order_by: [asc: a.inserted_at]
    )
  end

  @doc "Returns the full audit trail for a journal."
  def trail_for_journal(journal_id) do
    Repo.all(
      from a in AuditEvent,
        where: a.journal_id == ^journal_id,
        order_by: [asc: a.inserted_at]
    )
  end

  defp maybe_filter(query, key, opts) do
    case Keyword.get(opts, key) do
      nil -> query
      value -> where(query, [a], field(a, ^key) == ^value)
    end
  end
end
