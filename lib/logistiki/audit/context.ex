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

  @doc """
  Records a single audit event.

  ## Arguments

    * `attrs` — `map()` of audit event attributes:
        * `:action` — `String.t` — **required** (e.g. `"journal_posted"`)
        * `:event_id` — `String.t` — the originating event id
        * `:journal_id` — `integer()` — the related journal id
        * `:resource_type` — `String.t`
        * `:resource_id` — `String.t`
        * `:explanation` — `map()`
        * `:metadata` — `map()`

  ## Returns

    * `{:ok, %AuditEvent{}}` — the persisted audit event.
    * `{:error, %Ecto.Changeset{}}` — validation failed.

  ## Examples

      iex> {:ok, event} = Logistiki.Audit.record(%{action: "journal_posted", event_id: "evt_1"})
      iex> event.action
      "journal_posted"
  """
  @doc since: "0.1.0"
  @spec record(map()) :: {:ok, AuditEvent.t()} | {:error, Ecto.Changeset.t()}
  def record(attrs) do
    %AuditEvent{}
    |> AuditEvent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Records every stage in an `Evidence` struct as an audit event.

  ## Arguments

    * `evidence` — `%Logistiki.Audit.Evidence{}` — with `stages`, `event_id`,
      `journal_id`.

  ## Returns

    * `:ok` — all stages were recorded.

  ## Examples

      iex> evidence = Logistiki.Audit.Evidence.build("evt_1", journal_id, stages, %{})
      iex> Logistiki.Audit.record_evidence(evidence)
      :ok
  """
  @doc since: "0.1.0"
  @spec record_evidence(Evidence.t()) :: :ok
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

  @doc """
  Lists audit events, optionally filtered.

  ## Arguments

    * `opts` — `keyword()` of options:
        * `:event_id` — `String.t` — filter by event id
        * `:journal_id` — `integer()` — filter by journal id
        * `:action` — `String.t` — filter by action (e.g. `"journal_posted"`)

  ## Returns

    * `[AuditEvent.t()]` — ordered by `inserted_at` descending.

  ## Examples

      iex> Logistiki.Audit.list_audit_events(event_id: "evt_001")
      [%AuditEvent{action: "business_event_received", ...}, ...]

      iex> Logistiki.Audit.list_audit_events(action: "journal_posted")
      [%AuditEvent{action: "journal_posted", ...}]
  """
  @doc since: "0.1.0"
  @spec list_audit_events(keyword()) :: [AuditEvent.t()]
  def list_audit_events(opts \\ []) do
    AuditEvent
    |> maybe_filter(:event_id, opts)
    |> maybe_filter(:journal_id, opts)
    |> maybe_filter(:action, opts)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  @doc """
  Returns the full audit trail for a business event.

  ## Arguments

    * `event_id` — `String.t() | atom()` — the event id.

  ## Returns

    * `[AuditEvent.t()]` — ordered by `inserted_at` ascending, showing the
      full pipeline trace.

  ## Examples

      iex> trail = Logistiki.Audit.trail_for_event("evt_001")
      iex> Enum.map(trail, & &1.action)
      ["event_normalized", "business_event_received", "facts_generated", ...]
  """
  @doc since: "0.1.0"
  @spec trail_for_event(String.t() | atom()) :: [AuditEvent.t()]
  def trail_for_event(event_id) do
    Repo.all(
      from a in AuditEvent,
        where: a.event_id == ^to_string(event_id),
        order_by: [asc: a.inserted_at]
    )
  end

  @doc """
  Returns the full audit trail for a journal.

  ## Arguments

    * `journal_id` — `integer()` — the journal id.

  ## Returns

    * `[AuditEvent.t()]` — ordered by `inserted_at` ascending.

  ## Examples

      iex> trail = Logistiki.Audit.trail_for_journal(1)
      iex> Enum.map(trail, & &1.action)
      ["journal_built", "invariant_validation_succeeded", "journal_posted", ...]
  """
  @doc since: "0.1.0"
  @spec trail_for_journal(integer()) :: [AuditEvent.t()]
  def trail_for_journal(journal_id) do
    Repo.all(
      from a in AuditEvent,
        where: a.journal_id == ^journal_id,
        order_by: [asc: a.inserted_at]
    )
  end

  # maybe_filter — applies an optional equality filter from opts to query.
  defp maybe_filter(query, key, opts) do
    case Keyword.get(opts, key) do
      nil -> query
      value -> where(query, [a], field(a, ^key) == ^value)
    end
  end
end
