defmodule Logistiki.Accounting.Pipeline do
  @moduledoc """
  The accounting pipeline: the defining mental model of Logistiki.

      Business Event
          │
          ▼
      Event Normalization
          │
          ▼
      Idempotency / Outcome Lookup
          │
          ▼
      Datalog Fact Generation
          │
          ▼
      Business Rule Evaluation
          │
          ▼
      Accounting Policy Selection
          │
          ▼
      Accounting Template Resolution
          │
          ▼
      Journal Builder
          │
          ▼
      Posting Builder
          │
          ▼
      Ledger Invariant Validation
          │
          ▼
      Atomic Commit (event + journal + postings + provenance)
          │
          ▼
      Async enriched audit drain

  Pure decision stages run outside the database transaction. Durable writes for
  accepted outcomes go through `Logistiki.Accounting.Commit`.
  """

  alias Logistiki.Accounting.{Commit, InvariantValidator, JournalBuilder, Outcome, Result}
  alias Logistiki.Audit
  alias Logistiki.Error
  alias Logistiki.Event
  alias Logistiki.Knowledge
  alias Logistiki.Ledger
  alias Logistiki.Ledger.Beancount, as: BeancountBackend
  alias Logistiki.Projections.ProjectionEngine
  alias Logistiki.Telemetry

  @doc """
  Runs the full accounting pipeline for `event` (a business event struct).

  Returns `{:ok, %Logistiki.Accounting.Result{}}` or `{:error, %Logistiki.Error{}}`.
  """
  @doc since: "0.1.0"
  def run(event, opts \\ []) do
    start_mono = Telemetry.start([:logistiki, :event, :process], %{event_type: event_type(event)})

    with {:ok, normalized, s1} <- normalize_stage(event),
         {:ok, normalized} <- require_event_identity(normalized),
         :proceed <- Outcome.resolve_idempotency(normalized),
         {:ok, knowledge_result, s3} <- knowledge_stage(normalized),
         {:ok, s4} <- business_rules_stage(knowledge_result, normalized),
         {:ok, journal, postings, explanation, s5} <- journal_stage(knowledge_result, normalized),
         {:ok, s6} <- invariant_stage(journal, postings),
         {:ok, result} <-
           finish_accounting(
             %{
               event: event,
               normalized: normalized,
               knowledge_result: knowledge_result,
               stages: [s1, s3, s4, s5, s6],
               opts: opts,
               start_mono: start_mono
             },
             journal,
             postings,
             explanation
           ) do
      {:ok, result}
    else
      {:replay, %Result{} = result} ->
        Telemetry.stop([:logistiki, :event, :process], start_mono, %{
          outcome: :already_processed,
          event_id: result.event_id
        })

        Telemetry.emit([:logistiki, :commit, :stop], %{count: 1}, %{outcome: :duplicate})
        {:ok, result}

      {:no_impact, normalized, pre_stages} ->
        case Commit.decision(%{
               event: event,
               normalized: normalized,
               status: "no_accounting_impact",
               stages: pre_stages,
               explanation: %{reason: :no_accounting_impact}
             }) do
          {:ok, _} ->
            Telemetry.stop([:logistiki, :event, :process], start_mono, %{policy: nil})
            Telemetry.emit([:logistiki, :commit, :stop], %{count: 1}, %{outcome: :accepted})
            Audit.drain_pending_async(normalized.id)

            {:ok,
             %Result{
               event_id: normalized.id,
               policy: nil,
               template: nil,
               journal: nil,
               postings: [],
               ledger_result: nil,
               projection_updates: %{},
               audit_evidence_id: normalized.id,
               warnings: [],
               explanation: %{reason: :no_accounting_impact}
             }}

          {:error, %Error{} = error} ->
            emit_failure(start_mono, error)
            {:error, error}
        end

      {:blocked, %Error{} = error, normalized, stages} ->
        status =
          if error.code == :approval_required, do: "requires_approval", else: "blocked"

        case Commit.decision(%{
               event: event,
               normalized: normalized,
               status: status,
               stages: stages,
               explanation: %{code: error.code, message: error.message}
             }) do
          {:ok, _} ->
            emit_failure(start_mono, error)
            Telemetry.emit([:logistiki, :commit, :stop], %{count: 1}, %{outcome: :rejected})
            Audit.drain_pending_async(normalized.id)
            {:error, error}

          {:error, %Error{} = persist_error} ->
            emit_failure(start_mono, persist_error)
            {:error, persist_error}
        end

      {:error, %Error{} = error} ->
        emit_failure(start_mono, error)
        {:error, error}
    end
  end

  # ------------------------------------------------------------------
  # Stages
  # ------------------------------------------------------------------

  defp normalize_stage(event) do
    case Event.normalize(event) do
      {:ok, normalized} ->
        Telemetry.emit([:logistiki, :event, :normalize, :stop], %{}, %{event_type: normalized.type})

        {:ok, normalized,
         %{
           action: :event_normalized,
           resource_type: :event,
           resource_id: normalized.id,
           explanation: %{event_type: normalized.type}
         }}

      {:error, reason} ->
        {:error,
         Error.new(:invalid_event,
           message: "event normalization failed: #{inspect(reason)}",
           stage: :normalization
         )}
    end
  end

  defp require_event_identity(%{has_accounting_impact: true, id: id})
       when id in [nil, ""] do
    {:error,
     Error.new(:invalid_event,
       message: "accounting-impact events require a non-nil event.id for idempotency",
       stage: :normalization
     )}
  end

  defp require_event_identity(normalized), do: {:ok, normalized}

  defp knowledge_stage(normalized) do
    Telemetry.emit([:logistiki, :knowledge, :evaluate, :start], %{}, %{event_type: normalized.type})

    case Knowledge.evaluate(normalized) do
      {:ok, result} ->
        Telemetry.emit([:logistiki, :knowledge, :evaluate, :stop], %{}, %{
          event_type: normalized.type,
          policy: result.policy
        })

        {:ok, result,
         %{
           action: :facts_generated,
           resource_type: :knowledge,
           resource_id: normalized.id,
           explanation: result.explanation
         }}

      {:error, reason} ->
        {:error,
         Error.new(:no_policy_found,
           message: "knowledge evaluation failed: #{inspect(reason)}",
           stage: :policy_selection
         )}
    end
  end

  defp business_rules_stage(result, normalized) do
    stage = %{
      action: :business_rules_evaluated,
      resource_type: :event,
      resource_id: normalized.id,
      explanation: %{blocked: result.blocked, requires_approval: result.requires_approval}
    }

    cond do
      result.blocked ->
        {:blocked,
         Error.new(:blocked_event,
           message: "event #{normalized.type} was blocked by a business rule",
           stage: :business_rules
         ), normalized, [stage]}

      result.requires_approval ->
        {:blocked,
         Error.new(:approval_required,
           message: "event #{normalized.type} requires approval",
           stage: :business_rules
         ), normalized, [stage]}

      not normalized.has_accounting_impact ->
        {:no_impact, normalized,
         [
           stage,
           %{action: :no_accounting_impact, resource_type: :event, resource_id: normalized.id}
         ]}

      true ->
        {:ok, stage}
    end
  end

  defp journal_stage(%{policy: nil} = result, normalized) do
    {:ok, nil, [], JournalBuilder.build(result, normalized) |> elem(2),
     %{
       action: :policy_selected,
       resource_type: :policy,
       resource_id: nil,
       explanation: %{policy: nil}
     }}
  end

  defp journal_stage(result, normalized) do
    Telemetry.emit([:logistiki, :policy, :select, :stop], %{}, %{policy: result.policy})
    Telemetry.emit([:logistiki, :template, :select, :stop], %{}, %{template: result.template})

    case JournalBuilder.build(result, normalized) do
      {:ok, journal, postings, explanation} ->
        Telemetry.emit([:logistiki, :journal, :build, :stop], %{}, %{
          policy: result.policy,
          posting_count: length(postings)
        })

        {:ok, journal, postings, explanation,
         %{
           action: :journal_built,
           resource_type: :journal,
           resource_id: nil,
           explanation: %{
             policy: result.policy,
             template: result.template,
             posting_count: length(postings)
           }
         }}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp invariant_stage(nil, []) do
    {:ok,
     %{
       action: :invariant_validation_succeeded,
       resource_type: :journal,
       resource_id: nil,
       explanation: %{journal: nil}
     }}
  end

  defp invariant_stage(journal, postings) do
    case InvariantValidator.validate(journal, postings) do
      :ok ->
        Telemetry.emit([:logistiki, :invariant, :validate, :stop], %{}, %{result: :ok})

        {:ok,
         %{
           action: :invariant_validation_succeeded,
           resource_type: :journal,
           resource_id: nil,
           explanation: %{postings: length(postings)}
         }}

      {:error, %Error{} = error} ->
        Telemetry.emit([:logistiki, :invariant, :validate, :stop], %{}, %{result: :error})
        {:error, error}
    end
  end

  defp finish_accounting(ctx, nil, [], explanation) do
    %{
      event: event,
      normalized: normalized,
      knowledge_result: knowledge_result,
      stages: stages,
      start_mono: start_mono
    } = ctx

    case Commit.decision(%{
           event: event,
           normalized: normalized,
           status: "no_accounting_impact",
           stages: stages,
           explanation: explanation || %{reason: :no_accounting_impact}
         }) do
      {:ok, _} ->
        emit_no_impact_success(normalized, knowledge_result, explanation, start_mono)

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp finish_accounting(ctx, journal, postings, explanation) do
    %{
      event: event,
      normalized: normalized,
      knowledge_result: knowledge_result,
      stages: stages,
      opts: opts,
      start_mono: start_mono
    } = ctx

    with :ok <- maybe_verify_oracle(journal, postings),
         {:ok, commit_result} <-
           commit_posted(event, normalized, journal, postings, explanation, stages) do
      emit_posted_success(
        commit_result,
        normalized,
        knowledge_result,
        explanation,
        opts,
        start_mono
      )
    end
  end

  defp emit_no_impact_success(normalized, knowledge_result, explanation, start_mono) do
    Telemetry.stop([:logistiki, :event, :process], start_mono, %{policy: nil})
    Telemetry.emit([:logistiki, :commit, :stop], %{count: 1}, %{outcome: :accepted})
    Audit.drain_pending_async(normalized.id)

    {:ok,
     %Result{
       event_id: normalized.id,
       policy: knowledge_result.policy,
       template: knowledge_result.template,
       journal: nil,
       postings: [],
       ledger_result: nil,
       projection_updates: %{},
       audit_evidence_id: normalized.id,
       warnings: [],
       explanation: explanation || %{reason: :no_accounting_impact}
     }}
  end

  defp emit_posted_success(
         commit_result,
         normalized,
         knowledge_result,
         explanation,
         opts,
         start_mono
       ) do
    posted_journal = commit_result.journal
    posted_postings = commit_result.postings
    backend = Ledger.backend()

    ledger_result = %Ledger.Result{
      backend: backend,
      journal_id: posted_journal.id,
      status: :ok,
      posted_at: posted_journal.posted_at,
      balances: compute_balances(posted_journal, opts),
      details: ledger_details(posted_journal, backend)
    }

    Telemetry.stop([:logistiki, :event, :process], start_mono, %{
      event_type: normalized.type,
      policy: knowledge_result.policy,
      outcome: :posted
    })

    Telemetry.emit([:logistiki, :commit, :stop], %{count: 1}, %{
      outcome: :posted,
      event_type: normalized.type
    })

    Audit.drain_pending_async(normalized.id)

    {:ok,
     %Result{
       event_id: normalized.id,
       policy: knowledge_result.policy,
       template: knowledge_result.template,
       journal: posted_journal,
       postings: posted_postings,
       ledger_result: ledger_result,
       projection_updates: ledger_result.balances,
       audit_evidence_id: normalized.id,
       warnings: [],
       explanation: explanation
     }}
  end

  defp ledger_details(journal, BeancountBackend) do
    %{journal: journal, oracle: :beancount}
  end

  defp ledger_details(journal, _backend), do: %{journal: journal}

  defp maybe_verify_oracle(journal, postings) do
    case Ledger.backend() do
      BeancountBackend ->
        BeancountBackend.verify_journal(journal, postings)

      _ ->
        :ok
    end
  end

  defp commit_posted(event, normalized, journal, postings, explanation, stages) do
    case Commit.post(%{
           event: event,
           normalized: normalized,
           journal: journal,
           postings: postings,
           stages: stages,
           explanation: explanation
         }) do
      {:ok, %{journal: j, postings: posts}} ->
        Telemetry.emit([:logistiki, :ledger, :execute, :stop], %{}, %{
          backend: Ledger.backend(),
          journal_id: j.id
        })

        {:ok, %{journal: %{j | postings: posts}, postings: posts}}

      {:error, %Error{code: :duplicate_idempotency_key}} ->
        case Outcome.resolve_idempotency(normalized) do
          {:replay, result} ->
            {:replay, result}

          :proceed ->
            # Unique race lost but prior row not yet visible — typed duplicate.
            {:error,
             Error.new(:duplicate_idempotency_key,
               message: "concurrent duplicate commit",
               stage: :persistence
             )}

          other ->
            other
        end

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp compute_balances(journal, opts) do
    (journal.postings || [])
    |> Enum.map(& &1.account_code)
    |> Enum.uniq()
    |> Map.new(fn code ->
      case ProjectionEngine.balance(code, opts) do
        {:ok, balances} -> {code, balances}
        {:error, _} -> {code, []}
      end
    end)
  end

  defp emit_failure(start_mono, %Error{} = error) do
    Telemetry.stop([:logistiki, :event, :process], start_mono, %{error: error.code})
    Telemetry.emit([:logistiki, :commit, :stop], %{count: 1}, %{outcome: :failed, code: error.code})
  end

  defp event_type(%{type: type}) when not is_nil(type), do: type

  defp event_type(event) do
    case Event.normalize(event) do
      {:ok, normalized} -> normalized.type
      _ -> nil
    end
  rescue
    _ -> nil
  end
end
