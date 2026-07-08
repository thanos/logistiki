defmodule Logistiki.Knowledge.KnowledgeBase do
  @moduledoc """
  Loads and evaluates the accounting knowledge program for a single event.

  Given a normalized event, this module:

    1. generates runtime facts (`Logistiki.Knowledge.Facts`)
    2. builds a program from `Logistiki.Knowledge.Program` (with static facts)
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

  @doc """
  Materializes the knowledge program with the runtime facts for `event`.

  ## Arguments

    * `normalized_event` — `%Logistiki.Event.Normalized{}`.
    * `opts` — `keyword()` — passed to `ExDatalog.materialize/2`.

  ## Returns

    * `{:ok, %ExDatalog.Knowledge{}}` — materialized knowledge with all derived
      facts.
    * `{:error, term()}` — materialization failed.

  ## Examples

      iex> {:ok, knowledge} = Logistiki.Knowledge.KnowledgeBase.materialize_for(normalized_event)
      iex> ExDatalog.Knowledge.get(knowledge, "policy")
      MapSet.new({:evt, :cash_deposit})
  """
  @doc since: "0.1.0"
  @spec materialize_for(Logistiki.Event.Normalized.t(), keyword()) ::
          {:ok, ExDatalog.Knowledge.t()} | {:error, term()}
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

  @doc """
  Evaluates the knowledge layer for `normalized_event` and interprets the result.

  ## Arguments

    * `normalized_event` — `%Logistiki.Event.Normalized{}`.
    * `opts` — `keyword()` — passed to `ExDatalog.materialize/2`.

  ## Returns

    * `{:ok, %Logistiki.Knowledge.Result{}}` — the interpreted result with
      `policy`, `template_postings`, `account_roles`, `blocked`, etc.
    * `{:error, term()}` — materialization failed.

  ## Examples

      iex> {:ok, result} = Logistiki.Knowledge.KnowledgeBase.evaluate(normalized_event)
      iex> result.policy
      :cash_deposit
  """
  @doc since: "0.1.0"
  @spec evaluate(Logistiki.Event.Normalized.t(), keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def evaluate(normalized_event, opts \\ []) do
    with {:ok, knowledge} <- materialize_for(normalized_event, opts) do
      {:ok, interpret(knowledge, normalized_event)}
    end
  end

  @doc """
  Interprets materialized knowledge into a `Logistiki.Knowledge.Result`.

  Extracts derived policies, account roles, template postings, and required
  dimensions, selects the policy (unique, first-sorted on ambiguity, or nil),
  and builds the `Result`.

  ## Arguments

    * `knowledge` — `%ExDatalog.Knowledge{}` — materialized knowledge.
    * `normalized_event` — `%Logistiki.Event.Normalized{}` — for the event id.

  ## Returns

    * `%Logistiki.Knowledge.Result{}` — the interpreted result.

  ## Examples

      iex> {:ok, knowledge} = Logistiki.Knowledge.KnowledgeBase.materialize_for(normalized_event)
      iex> result = Logistiki.Knowledge.KnowledgeBase.interpret(knowledge, normalized_event)
      iex> result.policy
      :cash_deposit
  """
  @doc since: "0.1.0"
  @spec interpret(ExDatalog.Knowledge.t(), Logistiki.Event.Normalized.t()) :: Result.t()
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

  # Selects the policy from the derived list. Returns {policy, explanation}.
  # No candidates -> {nil, :no_policy_found}. One -> unique. Multiple ->
  # sorted, first wins, with an ambiguity warning.
  defp select_policy([]), do: {nil, %{reason: :no_policy_found, candidates: []}}

  defp select_policy([policy]) do
    {policy, %{reason: :unique, selected: policy}}
  end

  defp select_policy(policies) do
    {Enum.sort(policies) |> hd(),
     %{reason: :ambiguous_policy_resolved_to_first, candidates: policies}}
  end

  # Filters template postings to those for `policy`, sorted by sequence.
  defp postings_for_policy(_all_postings, nil), do: []

  defp postings_for_policy(all_postings, policy) do
    all_postings
    |> Enum.filter(fn p -> p.policy == policy end)
    |> Enum.sort_by(& &1.sequence)
  end

  # Adds runtime facts to the Datalog program by piping `Program.add_fact/3`.
  defp add_facts(program, facts) do
    Enum.reduce(facts, program, fn {relation, values}, acc ->
      DatalogProgram.add_fact(acc, Atom.to_string(relation), values)
    end)
  end

  @doc """
  Returns the raw `ExDatalog.Knowledge` for inspection/debugging.

  ## Arguments

    * `normalized_event` — `%Logistiki.Event.Normalized{}`.
    * `opts` — `keyword()` — passed to `ExDatalog.materialize/2`.

  ## Returns

    * `{:ok, %ExDatalog.Knowledge{}}` | `{:error, term()}`

  ## Examples

      iex> {:ok, knowledge} = Logistiki.Knowledge.KnowledgeBase.raw_knowledge(normalized_event)
  """
  @doc since: "0.1.0"
  @spec raw_knowledge(Logistiki.Event.Normalized.t(), keyword()) ::
          {:ok, ExDatalog.Knowledge.t()} | {:error, term()}
  def raw_knowledge(normalized_event, opts \\ []) do
    materialize_for(normalized_event, opts)
  end

  @doc """
  Lists all derived policy facts for an event (useful for tests).

  ## Arguments

    * `knowledge` — `%ExDatalog.Knowledge{}`.

  ## Returns

    * `[atom()]` — the derived policy atoms.

  ## Examples

      iex> Logistiki.Knowledge.KnowledgeBase.derived_policies(knowledge)
      [:cash_deposit]
  """
  @doc since: "0.1.0"
  @spec derived_policies(ExDatalog.Knowledge.t()) :: [atom()]
  def derived_policies(knowledge), do: Query.policies(knowledge)

  @doc """
  Lists all derived account roles for an event.

  ## Arguments

    * `knowledge` — `%ExDatalog.Knowledge{}`.

  ## Returns

    * `%{atom() => String.t()}` — role-to-code map.

  ## Examples

      iex> Logistiki.Knowledge.KnowledgeBase.derived_account_roles(knowledge)
      %{cash_account: "ASSETS:CASH:USD:NOSTRO"}
  """
  @doc since: "0.1.0"
  @spec derived_account_roles(ExDatalog.Knowledge.t()) :: %{atom() => String.t()}
  def derived_account_roles(knowledge), do: Query.account_roles(knowledge)
end
