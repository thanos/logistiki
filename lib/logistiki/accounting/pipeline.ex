defmodule Logistiki.Accounting.Pipeline do
  @moduledoc """
  The accounting pipeline: the defining mental model of Logistiki.

      Business Event
          │
          ▼
      Event Normalization
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
      Ledger Backend Execution
          │
          ▼
      Projection Generation
          │
          ▼
      Audit Evidence

  Each stage is represented here and recorded in the audit trail.
  """

  alias Logistiki.Accounting.{InvariantValidator, JournalBuilder, Result}
  alias Logistiki.Audit
  alias Logistiki.Audit.Evidence
  alias Logistiki.Error
  alias Logistiki.Event
  alias Logistiki.Events
  alias Logistiki.Knowledge
  alias Logistiki.Ledger
  alias Logistiki.Telemetry

  @doc """
  Runs the full accounting pipeline for `event` (a business event struct).

  Returns `{:ok, %Logistiki.Accounting.Result{}}` or `{:error, %Logistiki.Error{}}`.
  """
  @doc since: "0.1.0"
  def run(event, opts \\ []) do
    start_mono = Telemetry.start([:logistiki, :event, :process], %{event_type: event_type(event)})

    with {:ok, normalized, s1} <- normalize_stage(event),
         {:ok, persisted_event, s2} <- persist_stage(normalized, event),
         {:ok, knowledge_result, s3} <- knowledge_stage(normalized),
         {:ok, s4} <- business_rules_stage(knowledge_result, normalized),
         {:ok, journal, postings, explanation, s5} <- journal_stage(knowledge_result, normalized),
         {:ok, s6} <- invariant_stage(journal, postings),
         {:ok, ledger_result, s7} <- ledger_stage(journal, postings, opts) do
      stages = [s1, s2, s3, s4, s5, s6, s7]

      Telemetry.stop([:logistiki, :event, :process], start_mono, %{
        event_type: normalized.type,
        policy: knowledge_result.policy
      })

      {:ok, audit_evidence_id, _} = audit_stage(normalized, journal, ledger_result, stages)

      result = %Result{
        event_id: normalized.id,
        policy: knowledge_result.policy,
        template: knowledge_result.template,
        journal: ledger_result && ledger_result.details[:journal],
        postings: postings,
        ledger_result: ledger_result,
        projection_updates: projection_updates(ledger_result),
        audit_evidence_id: audit_evidence_id,
        warnings: warnings_for(knowledge_result),
        explanation: explanation
      }

      maybe_update_event_status(persisted_event, result)

      {:ok, result}
    else
      {:error, %Error{} = error} ->
        Telemetry.stop([:logistiki, :event, :process], start_mono, %{error: error.code})
        {:error, error}

      {:blocked, %Error{} = error} ->
        Telemetry.stop([:logistiki, :event, :process], start_mono, %{error: error.code})
        {:error, error}

      {:no_impact, normalized, pre_stages} ->
        Telemetry.stop([:logistiki, :event, :process], start_mono, %{policy: nil})

        stages =
          pre_stages ++
            [%{action: :no_accounting_impact, resource_type: :event, resource_id: normalized.id}]

        {:ok, audit_evidence_id, _} = audit_stage(normalized, nil, nil, stages)

        {:ok,
         %Result{
           event_id: normalized.id,
           policy: nil,
           template: nil,
           journal: nil,
           postings: [],
           ledger_result: nil,
           projection_updates: %{},
           audit_evidence_id: audit_evidence_id,
           warnings: [],
           explanation: %{reason: :no_accounting_impact}
         }}
    end
  end

  # ------------------------------------------------------------------
  # Stages
  # ------------------------------------------------------------------

  # normalize_stage — private helper.
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

  # persist_stage — private helper.
  defp persist_stage(normalized, event) do
    case Events.persist(event) do
      {:ok, persisted} ->
        {:ok, persisted,
         %{
           action: :business_event_received,
           resource_type: :business_event,
           resource_id: persisted.id,
           explanation: %{event_type: normalized.type, source_system: normalized.source_system}
         }}

      {:error, _reason} ->
        # Persistence failure is non-fatal for processing; carry on with a nil record.
        {:ok, nil,
         %{
           action: :business_event_received,
           resource_type: :business_event,
           resource_id: nil,
           explanation: %{event_type: normalized.type, persisted: false}
         }}
    end
  end

  # knowledge_stage — private helper.
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

  # business_rules_stage — private helper.
  defp business_rules_stage(result, normalized) do
    cond do
      result.blocked ->
        {:blocked,
         Error.new(:blocked_event,
           message: "event #{normalized.type} was blocked by a business rule",
           stage: :business_rules
         )}

      result.requires_approval ->
        {:blocked,
         Error.new(:approval_required,
           message: "event #{normalized.type} requires approval",
           stage: :business_rules
         )}

      not normalized.has_accounting_impact ->
        {:no_impact, normalized,
         [%{action: :no_accounting_impact, resource_type: :event, resource_id: normalized.id}]}

      true ->
        {:ok,
         %{
           action: :business_rules_evaluated,
           resource_type: :event,
           resource_id: normalized.id,
           explanation: %{blocked: false, requires_approval: false}
         }}
    end
  end

  # journal_stage — private helper.
  defp journal_stage(%{policy: nil} = result, normalized) do
    {:ok, nil, [], JournalBuilder.build(result, normalized) |> elem(2),
     %{
       action: :policy_selected,
       resource_type: :policy,
       resource_id: nil,
       explanation: %{policy: nil}
     }}
  end

  # journal_stage — private helper.
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

  # invariant_stage — private helper.
  defp invariant_stage(nil, []) do
    {:ok,
     %{
       action: :invariant_validation_succeeded,
       resource_type: :journal,
       resource_id: nil,
       explanation: %{journal: nil}
     }}
  end

  # invariant_stage — private helper.
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

  # ledger_stage — private helper.
  defp ledger_stage(nil, [], _opts) do
    {:ok, nil,
     %{
       action: :ledger_backend_execution_skipped,
       resource_type: :journal,
       resource_id: nil,
       explanation: %{}
     }}
  end

  # ledger_stage — private helper.
  defp ledger_stage(journal, postings, opts) do
    backend = Ledger.backend()
    journal_with_postings = %{journal | postings: postings}

    Telemetry.emit([:logistiki, :ledger, :execute, :start], %{}, %{backend: backend})

    case backend.execute_journal(journal_with_postings, opts) do
      {:ok, ledger_result} ->
        Telemetry.emit([:logistiki, :ledger, :execute, :stop], %{}, %{
          backend: backend,
          journal_id: ledger_result.journal_id
        })

        {:ok, ledger_result,
         %{
           action: :journal_posted,
           resource_type: :journal,
           resource_id: ledger_result.journal_id,
           explanation: %{backend: backend, status: ledger_result.status}
         }}

      {:error, %Error{} = error} ->
        Telemetry.emit([:logistiki, :ledger, :execute, :stop], %{}, %{
          backend: backend,
          result: :error
        })

        {:error, error}
    end
  end

  # audit_stage — private helper.
  defp audit_stage(normalized, journal, ledger_result, stages) do
    journal_id = (ledger_result && ledger_result.journal_id) || (journal && journal.id)

    evidence =
      Evidence.build(normalized.id, journal_id, stages, %{
        event_type: normalized.type,
        ledger_status: ledger_result && ledger_result.status
      })

    Audit.record_evidence(evidence)

    Audit.record(%{
      event_id: to_string(normalized.id),
      journal_id: journal_id,
      action: "audit_event_written",
      resource_type: "audit",
      resource_id: to_string(normalized.id),
      explanation: %{ledger_status: ledger_result && ledger_result.status}
    })

    Telemetry.emit([:logistiki, :audit, :write, :stop], %{}, %{event_id: normalized.id})

    {:ok, normalized.id,
     %{
       action: :audit_event_written,
       resource_type: :audit,
       resource_id: normalized.id,
       explanation: %{}
     }}
  end

  # projection_updates — private helper.
  defp projection_updates(ledger_result) do
    if ledger_result, do: ledger_result.balances, else: %{}
  end

  # warnings_for — private helper.
  defp warnings_for(%{requires_approval: false, blocked: false}), do: []

  # warnings_for — private helper.
  defp warnings_for(_), do: []

  # event_type — private helper.
  defp event_type(%{type: _}), do: nil

  # event_type — private helper.
  defp event_type(event) do
    {:ok, normalized} = Event.normalize(event)
    normalized.type
  rescue
    _ -> nil
  end

  # maybe_update_event_status — private helper.
  defp maybe_update_event_status(nil, _result), do: :ok

  # maybe_update_event_status — private helper.
  defp maybe_update_event_status(persisted, %Result{journal: nil}) do
    Events.update_status(persisted, :no_accounting_impact)
  end

  # maybe_update_event_status — private helper.
  defp maybe_update_event_status(persisted, %Result{}) do
    Events.update_status(persisted, :processed)
  end
end
