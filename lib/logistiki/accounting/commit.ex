defmodule Logistiki.Accounting.Commit do
  @moduledoc """
  Single Logistiki.Repo commit boundary for accounting outcomes.

  Accepted financial posts bind business event, journal, postings, and mandatory
  provenance audit in one `Ecto.Multi` transaction. Non-posting decisions
  (blocked, approval-required, no-impact) persist decision evidence without
  journals.
  """

  import Ecto.Query

  alias Ecto.Multi

  alias Logistiki.Accounting.{
    Fingerprint,
    InvariantValidator,
    Journal,
    JournalBuilder,
    Posting
  }

  alias Logistiki.Audit.AuditEvent
  alias Logistiki.Audit.AuditPending
  alias Logistiki.Error
  alias Logistiki.Event
  alias Logistiki.Events.BusinessEvent
  alias Logistiki.Repo
  alias Logistiki.VirtualAccounts

  @doc """
  Atomically posts a journal with its business event and mandatory provenance.

  Options / required keys in `attrs`:

    * `:event` — original event struct
    * `:normalized` — `%Event.Normalized{}`
    * `:journal` — draft `%Journal{}`
    * `:postings` — list of posting structs/maps
    * `:stages` — pipeline stage maps for enriched audit_pending
    * `:explanation` — optional map stored on the business event
  """
  @doc since: "0.1.1"
  @spec post(map()) :: {:ok, map()} | {:error, Error.t()}
  def post(attrs) when is_map(attrs) do
    event = Map.fetch!(attrs, :event)
    normalized = Map.fetch!(attrs, :normalized)
    journal = Map.fetch!(attrs, :journal)
    postings = Map.fetch!(attrs, :postings)
    stages = Map.get(attrs, :stages, [])
    explanation = Map.get(attrs, :explanation)

    case Application.get_env(:logistiki, :inject_commit_failure) do
      :event ->
        {:error,
         Error.new(:event_persist_failed,
           message: "injected event persistence failure",
           stage: :persistence
         )}

      :journal ->
        {:error,
         Error.new(:commit_failed,
           message: "injected journal persistence failure",
           stage: :persistence
         )}

      :audit ->
        {:error,
         Error.new(:audit_persist_failed,
           message: "injected mandatory audit failure",
           stage: :persistence
         )}

      _ ->
        do_post(event, normalized, journal, postings, stages, explanation)
    end
  end

  defp do_post(event, normalized, journal, postings, stages, explanation) do
    fingerprint = Fingerprint.compute(normalized)
    posted_at = DateTime.utc_now(:second)

    Multi.new()
    |> Multi.insert(
      :business_event,
      business_event_changeset(event, normalized, fingerprint, "processed", explanation)
    )
    |> Multi.run(:lock_accounts, fn repo, _ -> lock_and_check_accounts(repo, postings) end)
    |> Multi.insert(:journal, journal_insert_changeset(journal, posted_at))
    |> Multi.run(:postings, fn repo, %{journal: inserted_journal} ->
      insert_postings(repo, inserted_journal, postings)
    end)
    |> Multi.insert(:provenance, fn %{journal: inserted_journal, business_event: be} ->
      provenance_changeset(normalized, inserted_journal, be)
    end)
    |> Multi.run(:audit_pending, fn repo, %{journal: inserted_journal} ->
      enqueue_pending(repo, normalized, inserted_journal.id, stages)
    end)
    |> Repo.transaction()
    |> normalize_result()
  end

  @doc """
  Persists a non-posting decision (no-impact, blocked, approval-required, failed).
  """
  @doc since: "0.1.1"
  @spec decision(map()) :: {:ok, map()} | {:error, Error.t()}
  def decision(attrs) when is_map(attrs) do
    event = Map.fetch!(attrs, :event)
    normalized = Map.fetch!(attrs, :normalized)
    status = Map.fetch!(attrs, :status) |> to_string()
    stages = Map.get(attrs, :stages, [])
    explanation = Map.get(attrs, :explanation)
    fingerprint = Fingerprint.compute(normalized)

    Multi.new()
    |> Multi.insert(
      :business_event,
      business_event_changeset(event, normalized, fingerprint, status, explanation)
    )
    |> Multi.insert(:provenance, fn %{business_event: be} ->
      decision_provenance_changeset(normalized, be, status)
    end)
    |> Multi.run(:audit_pending, fn repo, _ ->
      enqueue_pending(repo, normalized, nil, stages)
    end)
    |> Repo.transaction()
    |> normalize_result()
  end

  @doc """
  Reverses a posted journal at most once under concurrency.
  """
  @doc since: "0.1.1"
  @spec reverse(Journal.t(), map()) :: {:ok, Journal.t()} | {:error, Error.t()}
  def reverse(journal, attrs \\ %{})

  def reverse(%Journal{status: "posted"} = journal, attrs) do
    postings = list_postings(journal)

    with {:ok, reversal, reversal_postings} <- safe_build_reversal(journal, postings, attrs),
         :ok <- InvariantValidator.validate_reversal(postings, reversal_postings) do
      posted_at = DateTime.utc_now(:second)

      Multi.new()
      |> Multi.run(:lock_original, fn repo, _ -> lock_posted_journal(repo, journal.id) end)
      |> Multi.run(:cas_reverse, fn repo, %{lock_original: locked} ->
        cas_mark_reversed(repo, locked.id, posted_at)
      end)
      |> Multi.insert(:reversal, journal_insert_changeset(reversal, posted_at))
      |> Multi.run(:postings, fn repo, %{reversal: inserted} ->
        insert_postings(repo, inserted, reversal_postings)
      end)
      |> Multi.insert(:provenance, fn %{reversal: inserted} ->
        %AuditEvent{}
        |> AuditEvent.changeset(%{
          event_id: inserted.event_id,
          journal_id: inserted.id,
          action: "commit_provenance",
          resource_type: "journal",
          resource_id: to_string(inserted.id),
          explanation: %{kind: :reversal, reversal_of_id: journal.id}
        })
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{reversal: rev, postings: posts}} ->
          {:ok, %{rev | postings: posts}}

        {:error, _step, reason, _changes} ->
          {:error, to_error(reason)}

        {:error, reason} ->
          {:error, to_error(reason)}
      end
    end
  end

  def reverse(%Journal{status: status}, _attrs) do
    {:error,
     Error.new(:immutable_journal, message: "only posted journals can be reversed, got #{status}")}
  end

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  defp business_event_changeset(event, normalized, fingerprint, status, explanation) do
    %BusinessEvent{}
    |> BusinessEvent.changeset(%{
      event_type: normalized.type,
      source_system: normalized.source_system,
      source_id: normalized.source_id,
      external_event_id: external_event_id(normalized),
      payload_fingerprint: fingerprint,
      actor_id: normalized.actor_id,
      occurred_at: normalized.occurred_at,
      effective_date: normalized.effective_date,
      payload: encode_payload(event),
      normalized_payload: Event.Normalized.to_map(normalized),
      status: status,
      explanation: explanation,
      metadata: Map.get(event, :metadata, %{})
    })
  end

  defp journal_insert_changeset(journal, posted_at) do
    journal
    |> Map.put(:postings, [])
    |> Journal.changeset(%{status: "posted", posted_at: posted_at})
  end

  defp provenance_changeset(normalized, journal, _business_event) do
    %AuditEvent{}
    |> AuditEvent.changeset(%{
      event_id: to_string(normalized.id),
      journal_id: journal.id,
      action: "commit_provenance",
      resource_type: "journal",
      resource_id: to_string(journal.id),
      explanation: %{kind: :posted, event_type: normalized.type}
    })
  end

  defp decision_provenance_changeset(normalized, business_event, status) do
    %AuditEvent{}
    |> AuditEvent.changeset(%{
      event_id: to_string(normalized.id),
      journal_id: nil,
      action: "commit_provenance",
      resource_type: "business_event",
      resource_id: to_string(business_event.id),
      explanation: %{kind: :decision, status: status, event_type: normalized.type}
    })
  end

  defp enqueue_pending(repo, normalized, journal_id, stages) do
    now = DateTime.utc_now(:second)

    rows =
      Enum.map(stages, fn stage ->
        %{
          event_id: to_string(normalized.id),
          journal_id: journal_id,
          action: to_string(stage.action),
          resource_type: stage[:resource_type] && to_string(stage[:resource_type]),
          resource_id: stage[:resource_id] && to_string(stage[:resource_id]),
          explanation: stage[:explanation],
          metadata: Map.get(stage, :metadata, %{}),
          status: "pending",
          attempts: 0,
          last_error: nil,
          inserted_at: now,
          updated_at: now
        }
      end)

    if rows == [] do
      {:ok, 0}
    else
      {count, _} = repo.insert_all(AuditPending, rows)
      {:ok, count}
    end
  end

  defp lock_and_check_accounts(repo, postings) do
    codes = Enum.map(postings, & &1.account_code) |> Enum.uniq()

    accounts =
      from(a in VirtualAccounts.VirtualAccount,
        where: a.code in ^codes,
        lock: "FOR UPDATE"
      )
      |> repo.all()

    by_code = Map.new(accounts, &{&1.code, &1})

    Enum.reduce_while(codes, {:ok, by_code}, fn code, {:ok, acc} ->
      check_locked_account(code, by_code, acc)
    end)
  end

  defp check_locked_account(code, by_code, acc) do
    case Map.get(by_code, code) do
      nil ->
        {:halt,
         {:error,
          Error.new(:account_not_found,
            message: "account #{inspect(code)} does not exist",
            details: %{account_code: code},
            stage: :persistence
          )}}

      account ->
        if VirtualAccounts.posting_account?(account) do
          {:cont, {:ok, acc}}
        else
          {:halt,
           {:error,
            Error.new(:account_not_postable,
              message: "account #{inspect(code)} is not postable at commit time",
              details: %{account_code: code, status: account.status},
              stage: :persistence
            )}}
        end
    end
  end

  defp insert_postings(repo, journal, postings) do
    account_codes = Enum.map(postings, & &1.account_code) |> Enum.uniq()

    account_by_code =
      from(a in VirtualAccounts.VirtualAccount, where: a.code in ^account_codes)
      |> repo.all()
      |> Map.new(&{&1.code, &1})

    postings
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {p, index}, {:ok, acc} ->
      account = Map.fetch!(account_by_code, p.account_code)
      sequence = if is_integer(p.sequence) and p.sequence > 0, do: p.sequence, else: index

      sequence =
        if Enum.any?(acc, &(&1.sequence == sequence)), do: index, else: sequence

      cs =
        Posting.changeset(%Posting{}, %{
          journal_id: journal.id,
          virtual_account_id: account.id,
          account_code: p.account_code,
          debit_credit: p.debit_credit,
          amount: p.amount,
          currency: p.currency,
          memo: p.memo,
          sequence: sequence,
          metadata: p.metadata || %{}
        })

      case repo.insert(cs) do
        {:ok, posting} -> {:cont, {:ok, acc ++ [posting]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp lock_posted_journal(repo, id) do
    case from(j in Journal, where: j.id == ^id, lock: "FOR UPDATE") |> repo.one() do
      %Journal{status: "posted"} = j ->
        {:ok, j}

      %Journal{status: status} ->
        {:error,
         Error.new(:immutable_journal,
           message: "only posted journals can be reversed, got #{status}"
         )}

      nil ->
        {:error, Error.new(:backend_error, message: "journal not found", stage: :persistence)}
    end
  end

  defp cas_mark_reversed(repo, id, posted_at) do
    {count, _} =
      from(j in Journal, where: j.id == ^id and j.status == "posted")
      |> repo.update_all(set: [status: "reversed", reversed_at: posted_at, updated_at: posted_at])

    if count == 1 do
      {:ok, id}
    else
      {:error,
       Error.new(:immutable_journal,
         message: "journal was already reversed or is not posted",
         stage: :persistence
       )}
    end
  end

  defp list_postings(%Journal{id: id}) do
    Repo.all(from(p in Posting, where: p.journal_id == ^id, order_by: [asc: p.sequence]))
  end

  defp safe_build_reversal(journal, postings, attrs) do
    case JournalBuilder.build_reversal(journal, postings, attrs) do
      {:ok, reversal, reversal_postings} -> {:ok, reversal, reversal_postings}
      other -> other
    end
  rescue
    e ->
      {:error,
       Error.new(:backend_error,
         message: "failed to build reversal: #{Exception.message(e)}",
         stage: :journal_builder
       )}
  end

  defp external_event_id(%{id: id}) when not is_nil(id), do: to_string(id)
  defp external_event_id(_), do: nil

  defp encode_payload(struct) when is_struct(struct) do
    struct
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new(fn {k, v} -> {k, encode_value(v)} end)
  end

  defp encode_payload(map) when is_map(map), do: map

  defp encode_value(%Decimal{} = d), do: Decimal.to_string(d)
  defp encode_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp encode_value(%Date{} = d), do: Date.to_iso8601(d)
  defp encode_value(v) when is_map(v), do: Map.new(v, fn {k, val} -> {k, encode_value(val)} end)
  defp encode_value(v), do: v

  defp normalize_result({:ok, changes}), do: {:ok, changes}

  defp normalize_result({:error, step, reason, _changes}) do
    {:error, map_step_error(step, reason)}
  end

  defp normalize_result({:error, reason}), do: {:error, to_error(reason)}

  defp map_step_error(:business_event, %Ecto.Changeset{} = cs) do
    if unique_error?(cs, :external_event_id) or unique_error?(cs, :source_id) or
         unique_error?(cs, :source_system) do
      Error.new(:duplicate_idempotency_key,
        message: "business event identity already committed",
        details: %{step: :business_event},
        stage: :persistence
      )
    else
      Error.new(:event_persist_failed,
        message: "business event persistence failed",
        details: %{errors: inspect(cs.errors)},
        stage: :persistence
      )
    end
  end

  defp map_step_error(:journal, %Ecto.Changeset{} = cs) do
    if unique_error?(cs, :idempotency_key) do
      Error.new(:duplicate_idempotency_key,
        message: "journal idempotency key already exists",
        stage: :persistence
      )
    else
      Error.new(:commit_failed,
        message: "journal persistence failed",
        details: %{errors: inspect(cs.errors)},
        stage: :persistence
      )
    end
  end

  defp map_step_error(:provenance, %Ecto.Changeset{} = cs) do
    Error.new(:audit_persist_failed,
      message: "mandatory audit provenance failed",
      details: %{errors: inspect(cs.errors)},
      stage: :persistence
    )
  end

  defp map_step_error(:reversal, %Ecto.Changeset{} = cs) do
    if unique_error?(cs, :reversal_of_id) or unique_error?(cs, :idempotency_key) do
      Error.new(:duplicate_idempotency_key,
        message: "reversal already exists for journal",
        stage: :persistence
      )
    else
      to_error(cs)
    end
  end

  defp map_step_error(_step, reason), do: to_error(reason)

  defp unique_error?(%Ecto.Changeset{errors: errors}, field) do
    Enum.any?(errors, fn
      {^field, {_msg, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  defp to_error(%Error{} = error), do: error

  defp to_error(%Ecto.Changeset{} = cs),
    do:
      Error.new(:commit_failed,
        message: "persistence failed",
        details: %{errors: inspect(cs.errors)},
        stage: :persistence
      )

  defp to_error(reason),
    do: Error.new(:commit_failed, message: inspect(reason), stage: :persistence)
end
