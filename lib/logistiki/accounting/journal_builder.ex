defmodule Logistiki.Accounting.JournalBuilder do
  @moduledoc """
  Builds a journal draft (and its posting changesets) from a knowledge result
  and a normalized event.

  The journal builder is the bridge between the knowledge layer (which decides
  facts and relationships) and the accounting runtime (which materializes
  Elixir structs). Datalog does not construct structs; this module does.

  The draft journal is `status: "draft"` and carries the selected policy,
  template, event id, idempotency key, and an explanation map. The postings are
  built by `Logistiki.Accounting.PostingBuilder` and validated by
  `Logistiki.Accounting.InvariantValidator` before posting.
  """

  alias Logistiki.Accounting.Journal
  alias Logistiki.Accounting.PostingBuilder
  alias Logistiki.Error
  alias Logistiki.Knowledge.Result, as: KnowledgeResult
  alias Logistiki.Event.Normalized

  @doc """
  Builds a draft journal struct (with postings attached) from a knowledge
  result and normalized event.

  Returns `{:ok, %Journal{}, explanation}` or `{:error, %Logistiki.Error{}}`.

  When the knowledge result has no policy (e.g. an event with no accounting
  impact), returns `{:ok, nil, [], explanation}`.
  """
  def build(%KnowledgeResult{policy: nil} = result, %Normalized{}) do
    {:ok, nil, [], explanation(result, nil)}
  end

  def build(%KnowledgeResult{} = result, %Normalized{} = event) do
    %KnowledgeResult{policy: policy, template: template, template_postings: postings, account_roles: roles} =
      result

    idempotency_key = idempotency_key(event, policy)

    journal = %Journal{
      event_id: event.id,
      source_system: event.source_system,
      source_type: event.type,
      source_id: event.source_id,
      selected_policy: Atom.to_string(policy),
      selected_template: Atom.to_string(template),
      description: description(event, policy),
      status: "draft",
      effective_date: event.effective_date,
      idempotency_key: idempotency_key,
      explanation: explanation(result, event),
      metadata: %{
        actor_id: event.actor_id,
        entity_id: event.entity_id,
        product_code: event.product_code
      }
    }

    case PostingBuilder.build(postings, roles, event.amount, event.currency, nil) do
      {:ok, posting_structs} ->
        {:ok, %{journal | postings: posting_structs}, posting_structs, explanation(result, event)}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  @doc "Builds a reversal journal struct that exactly negates `journal`'s postings."
  def build_reversal(%Journal{} = journal, postings, attrs) do
    reversal_postings = PostingBuilder.build_reversals(postings, nil)

    reversal = %Journal{
      event_id: journal.event_id,
      source_system: journal.source_system,
      source_type: journal.source_type,
      source_id: journal.source_id,
      selected_policy: journal.selected_policy,
      selected_template: journal.selected_template,
      description: attrs[:description] || "Reversal of journal #{journal.id}",
      status: "draft",
      effective_date: attrs[:effective_date] || Date.utc_today(),
      reversal_of_id: journal.id,
      idempotency_key: attrs[:idempotency_key] || "reversal:#{journal.idempotency_key}",
      explanation: %{
        reversal_of: journal.id,
        reason: attrs[:reason]
      },
      metadata: attrs[:metadata] || %{},
      postings: reversal_postings
    }

    {:ok, reversal, reversal_postings}
  end

  defp idempotency_key(%Normalized{id: nil}, policy), do: "policy:#{policy}:#{:rand.uniform(1_000_000_000)}"
  defp idempotency_key(%Normalized{id: event_id}, policy), do: "evt:#{event_id}:policy:#{policy}"

  defp description(%Normalized{type: type}, policy), do: "#{type} via #{policy}"

  defp explanation(%KnowledgeResult{} = result, %Normalized{} = event) do
    %{
      event_id: event && event.id,
      event_type: event && event.type,
      policy: result.policy,
      template: result.template,
      blocked: result.blocked,
      requires_approval: result.requires_approval,
      account_roles: result.account_roles,
      knowledge_explanation: result.explanation
    }
  end

  defp explanation(%KnowledgeResult{} = result, nil) do
    %{
      policy: nil,
      blocked: result.blocked,
      requires_approval: result.requires_approval,
      knowledge_explanation: result.explanation
    }
  end
end
