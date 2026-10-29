defmodule Logistiki.Accounting.Outcome do
  @moduledoc """
  Durable outcome lookup and idempotency replay for `Logistiki.process/1`.

  After a timeout or crash, callers reconcile with `lookup/1` using the same
  business event id or source identity — never a new idempotency key.
  """

  import Ecto.Query

  alias Logistiki.Accounting.{Fingerprint, Journal, Result}
  alias Logistiki.Error
  alias Logistiki.Event.Normalized
  alias Logistiki.Events.BusinessEvent
  alias Logistiki.Ledger
  alias Logistiki.Repo

  @doc """
  Looks up a durable outcome by `event_id` and/or `source_system`+`source_id`.

  Returns:

    * `{:ok, %Result{}}` — reconstructed outcome (may include `outcome: :already_processed`)
    * `{:error, :not_found}` — no durable event
    * `{:error, %Error{}}` — identity conflict with provided fingerprint
  """
  @doc since: "0.1.1"
  @spec lookup(map() | keyword()) :: {:ok, Result.t()} | {:error, :not_found | Error.t()}
  def lookup(ref) when is_list(ref), do: lookup(Map.new(ref))

  def lookup(%{} = ref) do
    case find_business_event(ref) do
      nil ->
        {:error, :not_found}

      %BusinessEvent{} = event ->
        with :ok <- maybe_check_fingerprint(event, ref) do
          {:ok, to_result(event, replay?: Map.get(ref, :replay?, true))}
        end
    end
  end

  @doc """
  Resolves idempotency before a new commit.

  Returns:

    * `:proceed` — no prior durable event
    * `{:replay, %Result{}}` — same fingerprint, return original
    * `{:error, %Error{code: :idempotency_conflict}}` — same key, different payload
  """
  @doc since: "0.1.1"
  @spec resolve_idempotency(Normalized.t()) ::
          :proceed | {:replay, Result.t()} | {:error, Error.t()}
  def resolve_idempotency(%Normalized{} = normalized) do
    fingerprint = Fingerprint.compute(normalized)

    case find_business_event(%{
           event_id: normalized.id && to_string(normalized.id),
           source_system: normalized.source_system,
           source_id: normalized.source_id
         }) do
      nil ->
        :proceed

      %BusinessEvent{payload_fingerprint: ^fingerprint} = event ->
        {:replay, to_result(event, replay?: true)}

      %BusinessEvent{} = event ->
        {:error, idempotency_conflict_error(event, fingerprint)}
    end
  end

  defp find_business_event(%{} = ref) do
    event_id = ref[:event_id] || ref["event_id"]
    source_system = ref[:source_system] || ref["source_system"]
    source_id = ref[:source_id] || ref["source_id"]

    find_by_event_id(event_id) || find_by_source(source_system, source_id)
  end

  defp find_by_event_id(event_id) when is_binary(event_id) and event_id != "" do
    Repo.one(
      from(e in BusinessEvent,
        where: e.external_event_id == ^event_id,
        order_by: [desc: e.id],
        limit: 1
      )
    )
  end

  defp find_by_event_id(_), do: nil

  defp find_by_source(source_system, source_id)
       when is_binary(source_system) and is_binary(source_id) do
    Repo.one(
      from(e in BusinessEvent,
        where: e.source_system == ^source_system and e.source_id == ^source_id,
        order_by: [desc: e.id],
        limit: 1
      )
    )
  end

  defp find_by_source(_, _), do: nil

  defp maybe_check_fingerprint(_event, %{fingerprint: nil}), do: :ok
  defp maybe_check_fingerprint(_event, ref) when not is_map_key(ref, :fingerprint), do: :ok

  defp maybe_check_fingerprint(%BusinessEvent{payload_fingerprint: fp}, %{fingerprint: expected})
       when fp == expected,
       do: :ok

  defp maybe_check_fingerprint(%BusinessEvent{}, %{fingerprint: _}) do
    {:error,
     Error.new(:idempotency_conflict,
       message: "looked-up event fingerprint does not match",
       stage: :persistence
     )}
  end

  defp to_result(%BusinessEvent{} = event, opts) do
    replay? = Keyword.get(opts, :replay?, true)
    journal = pick_journal(journals_for_event(event))
    postings = journal_postings(journal)

    %Result{
      event_id: event.external_event_id || get_in(event.normalized_payload, ["id"]),
      policy: maybe_atom(journal && journal.selected_policy),
      template: maybe_atom(journal && journal.selected_template),
      journal: journal,
      postings: postings,
      ledger_result: build_ledger_result(journal, replay?),
      projection_updates: %{},
      audit_evidence_id: event.external_event_id,
      warnings: [],
      explanation: build_explanation(event, replay?)
    }
  end

  defp pick_journal(journals) do
    Enum.find(journals, &(&1.status == "posted")) ||
      Enum.find(journals, &(&1.status == "reversed")) ||
      List.first(journals)
  end

  defp journal_postings(nil), do: []
  defp journal_postings(journal), do: journal.postings || []

  defp build_explanation(%BusinessEvent{} = event, replay?) do
    event.explanation
    |> explanation_map()
    |> atomize_known_keys()
    |> normalize_explanation_values()
    |> maybe_put_replay(replay?)
    |> maybe_put_no_impact(event.status)
  end

  defp explanation_map(%{} = map), do: map
  defp explanation_map(_), do: %{}

  defp maybe_put_replay(map, true), do: Map.put(map, :outcome, :already_processed)
  defp maybe_put_replay(map, false), do: map

  defp maybe_put_no_impact(map, "no_accounting_impact") do
    Map.put(map, :reason, :no_accounting_impact)
  end

  defp maybe_put_no_impact(map, _), do: map

  defp build_ledger_result(nil, _replay?), do: nil

  defp build_ledger_result(journal, replay?) do
    %Ledger.Result{
      backend: Ledger.backend(),
      journal_id: journal.id,
      status: :ok,
      posted_at: journal.posted_at,
      balances: %{},
      details: %{journal: journal, replay: replay?}
    }
  end

  defp journals_for_event(%BusinessEvent{external_event_id: id}) when is_binary(id) do
    from(j in Journal,
      where: j.event_id == ^id,
      order_by: [asc: j.id],
      preload: [:postings]
    )
    |> Repo.all()
  end

  defp journals_for_event(_), do: []

  defp maybe_atom(nil), do: nil

  defp maybe_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end

  defp maybe_atom(value) when is_atom(value), do: value

  defp atomize_known_keys(map) do
    Map.new(map, fn {k, v} -> {atomize_key(k), v} end)
  end

  defp atomize_key(k) when is_atom(k), do: k

  defp atomize_key(k) when is_binary(k) do
    String.to_existing_atom(k)
  rescue
    ArgumentError -> k
  end

  defp atomize_key(k), do: k

  defp normalize_explanation_values(map) do
    Map.new(map, fn
      {:reason, value} when is_binary(value) -> {:reason, existing_atom(value)}
      {:outcome, value} when is_binary(value) -> {:outcome, existing_atom(value)}
      other -> other
    end)
  end

  defp existing_atom(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp idempotency_conflict_error(event, fingerprint) do
    Error.new(:idempotency_conflict,
      message: "same event identity with a different payload fingerprint",
      details: %{
        external_event_id: event.external_event_id,
        source_system: event.source_system,
        source_id: event.source_id,
        existing_fingerprint: event.payload_fingerprint,
        new_fingerprint: fingerprint
      },
      stage: :persistence
    )
  end
end
