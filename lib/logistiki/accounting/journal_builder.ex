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

  When the knowledge result has no policy (e.g. an event with no accounting
  impact), returns `{:ok, nil, [], explanation}`.

  ## Arguments

    * `result` — `%Logistiki.Knowledge.Result{}` — the knowledge layer output.
    * `event` — `%Logistiki.Event.Normalized{}` — the flattened event.

  ## Returns

    * `{:ok, %Journal{}, [Posting.t()], map()}` — the draft journal, its
      postings, and the explanation map.
    * `{:ok, nil, [], map()}` — no accounting impact (policy is nil).
    * `{:error, %Error{}}` — a posting could not be built (missing role).

  ## Examples

      iex> {:ok, journal, postings, explanation} = Logistiki.Accounting.JournalBuilder.build(knowledge_result, normalized_event)
      iex> journal.status
      "draft"
      iex> journal.selected_policy
      "cash_deposit"
      iex> length(postings)
      2
  """
  @doc since: "0.1.0"
  @spec build(KnowledgeResult.t(), Normalized.t()) ::
          {:ok, Journal.t() | nil, [Posting.t()], map()} | {:error, Error.t()}
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

  @doc """
  Builds a reversal journal struct that exactly negates `journal`'s postings.

  ## Arguments

    * `journal` — `%Journal{}` — the posted journal to reverse.
    * `postings` — `[Posting.t()]` — the original journal's postings.
    * `attrs` — `keyword()` or `map()` of options:
        * `:description` — `String.t` — defaults to `"Reversal of journal <id>"`
        * `:effective_date` — `Date.t` — defaults to `Date.utc_today/0`
        * `:idempotency_key` — `String.t` — defaults to `"reversal:<original_key>"`
        * `:reason` — `String.t` — the reason for the reversal
        * `:metadata` — `map()`

  ## Returns

    * `{:ok, %Journal{}, [Posting.t()]}` — the draft reversal journal and its
      reversal postings.

  ## Examples

      iex> {:ok, reversal, postings} = Logistiki.Accounting.JournalBuilder.build_reversal(journal, original_postings, reason: "mistaken fee")
      iex> reversal.reversal_of_id
      1
      iex> hd(postings).debit_credit
      "credit"
  """
  @doc since: "0.1.0"
  @spec build_reversal(Journal.t(), [Logistiki.Accounting.Posting.t()], keyword() | map()) ::
          {:ok, Journal.t(), [Logistiki.Accounting.Posting.t()]}
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

  # Generates an idempotency key from the event id and policy. When the event
  # has no id, a random suffix is used.
  defp idempotency_key(%Normalized{id: nil}, policy), do: "policy:#{policy}:#{:rand.uniform(1_000_000_000)}"
  defp idempotency_key(%Normalized{id: event_id}, policy), do: "evt:#{event_id}:policy:#{policy}"

  # Builds a human-readable description from the event type and policy.
  defp description(%Normalized{type: type}, policy), do: "#{type} via #{policy}"

  # Builds the explanation map recorded on the journal for audit/replay.
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

  # Builds the explanation for a no-accounting-impact event.
  defp explanation(%KnowledgeResult{} = result, nil) do
    %{
      policy: nil,
      blocked: result.blocked,
      requires_approval: result.requires_approval,
      knowledge_explanation: result.explanation
    }
  end
end
