defmodule Logistiki.Knowledge.KnowledgeBase do
  @moduledoc """
  Loads and evaluates the accounting knowledge program for a single event.

  Given a normalized event, this module:

    1. generates runtime facts (`Logistiki.Knowledge.Facts`)
    2. builds a blank program from `Logistiki.Knowledge.Program`
    3. adds the runtime facts
    4. materializes the Datalog knowledge
    5. interprets the result into a `Logistiki.Knowledge.Result`

  Datalog decides facts and relationships; Elixir interprets them.
  """

  alias ExDatalog.Program, as: DatalogProgram
  alias Logistiki.Knowledge.Facts
  alias Logistiki.Knowledge.Program
  alias Logistiki.Knowledge.Query
  alias Logistiki.Knowledge.Result

  @doc "Materializes the knowledge program with the runtime facts for `event`."
  def materialize_for(normalized_event, opts \\ []) do
    facts = Facts.generate(normalized_event)

    program =
      Program.program()
      |> add_facts(facts)

    case ExDatalog.materialize(program, opts) do
      {:ok, knowledge} -> {:ok, knowledge}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Evaluates the knowledge layer for `normalized_event` and interprets the result."
  def evaluate(normalized_event, opts \\ []) do
    with {:ok, knowledge} <- materialize_for(normalized_event, opts) do
      {:ok, interpret(knowledge, normalized_event)}
    end
  end

  @doc "Interprets materialized knowledge into a `Logistiki.Knowledge.Result`."
  def interpret(knowledge, normalized_event) do
    policies = Query.policies(knowledge)
    account_roles = Query.account_roles(knowledge)
    all_postings = Query.template_postings(knowledge)
    dimensions_by_policy = Query.required_dimensions(knowledge)

    {policy, explanation} = select_policy(policies)
    template = policy
    postings = postings_for_policy(all_postings, policy)
    required_dimensions = Map.get(dimensions_by_policy, policy, [])

    %Result{
      event_id: normalized_event.id,
      blocked: Query.blocked?(knowledge),
      requires_approval: Query.requires_approval?(knowledge),
      policy: policy,
      template: template,
      template_postings: postings,
      account_roles: account_roles,
      required_dimensions: required_dimensions,
      explanation: explanation
    }
  end

  defp select_policy([]), do: {nil, %{reason: :no_policy_found, candidates: []}}

  defp select_policy([policy]) do
    {policy, %{reason: :unique, selected: policy}}
  end

  defp select_policy(policies) do
    {Enum.sort(policies) |> hd(),
     %{reason: :ambiguous_policy_resolved_to_first, candidates: policies}}
  end

  defp postings_for_policy(_all_postings, nil), do: []

  defp postings_for_policy(all_postings, policy) do
    all_postings
    |> Enum.filter(fn p -> p.policy == policy end)
    |> Enum.sort_by(& &1.sequence)
  end

  defp add_facts(program, facts) do
    Enum.reduce(facts, program, fn {relation, values}, acc ->
      DatalogProgram.add_fact(acc, Atom.to_string(relation), values)
    end)
  end

  @doc "Returns the raw `ExDatalog.Knowledge` for inspection/debugging."
  def raw_knowledge(normalized_event, opts \\ []) do
    materialize_for(normalized_event, opts)
  end

  @doc "Lists all derived policy facts for an event (useful for tests)."
  def derived_policies(knowledge), do: Query.policies(knowledge)

  @doc "Lists all derived account roles for an event."
  def derived_account_roles(knowledge), do: Query.account_roles(knowledge)
end
