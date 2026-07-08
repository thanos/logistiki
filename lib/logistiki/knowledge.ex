defmodule Logistiki.Knowledge do
  @moduledoc """
  The context for the accounting knowledge layer.

  The knowledge layer is powered by `ex_datalog`. It contains business rules,
  accounting policies, posting templates, account mappings, and constraints.

  ## Public functions

    * `evaluate/1` — evaluate the knowledge program for a normalized event.
    * `load_program/0` — return the current knowledge program module.
    * `assert_fact/2` — (v0.1.0) record a runtime fact for the next evaluation.

  Datalog decides facts and relationships. Elixir materializes journals and
  postings.
  """

  alias Logistiki.Knowledge.KnowledgeBase

  @doc """
  Returns the configured knowledge program module.

  ## Returns

    * `module()` — defaults to `Logistiki.Knowledge.Program`. Override via
      `config :logistiki, :knowledge_program, MyCustomProgram`.

  ## Examples

      iex> Logistiki.Knowledge.load_program()
      Logistiki.Knowledge.Program
  """
  @doc since: "0.1.0"
  @spec load_program() :: module()
  def load_program do
    Application.get_env(:logistiki, :knowledge_program, Logistiki.Knowledge.Program)
  end

  @doc """
  Evaluates the knowledge program for `normalized_event`.

  Generates runtime facts, materializes the Datalog program, and interprets the
  result into a `%Logistiki.Knowledge.Result{}`.

  ## Arguments

    * `normalized_event` — `%Logistiki.Event.Normalized{}`.
    * `opts` — `keyword()` — passed through to `ExDatalog.materialize/2`
      (e.g. `storage: ExDatalog.Storage.ETS`).

  ## Returns

    * `{:ok, %Logistiki.Knowledge.Result{}}` — the evaluation succeeded.
    * `{:error, term()}` — materialization failed.

  ## Examples

      iex> {:ok, result} = Logistiki.Knowledge.evaluate(normalized_event)
      iex> result.policy
      :cash_deposit
      iex> result.account_roles[:cash_account]
      "ASSETS:CASH:USD:NOSTRO"
  """
  @doc since: "0.1.0"
  @spec evaluate(Logistiki.Event.Normalized.t(), keyword()) ::
          {:ok, Logistiki.Knowledge.Result.t()} | {:error, term()}
  def evaluate(normalized_event, opts \\ []) do
    KnowledgeBase.evaluate(normalized_event, opts)
  end

  @doc """
  Materializes the program and returns raw `ExDatalog.Knowledge`.

  Useful for debugging and testing — the raw knowledge lets you inspect all
  derived facts directly.

  ## Arguments

    * `normalized_event` — `%Logistiki.Event.Normalized{}`.
    * `opts` — `keyword()` — passed through to `ExDatalog.materialize/2`.

  ## Returns

    * `{:ok, %ExDatalog.Knowledge{}}` — the materialized knowledge.
    * `{:error, term()}` — materialization failed.

  ## Examples

      iex> {:ok, knowledge} = Logistiki.Knowledge.materialize(normalized_event)
      iex> ExDatalog.Knowledge.get(knowledge, "policy")
      MapSet.new({:evt, :cash_deposit})
  """
  @doc since: "0.1.0"
  @spec materialize(Logistiki.Event.Normalized.t(), keyword()) ::
          {:ok, ExDatalog.Knowledge.t()} | {:error, term()}
  def materialize(normalized_event, opts \\ []) do
    KnowledgeBase.materialize_for(normalized_event, opts)
  end

  @doc """
  Asserts a runtime fact to be added to the next materialization.

  In v0.1.0 this is a convenience that returns the fact tuple for use with
  `Logistiki.Knowledge.KnowledgeBase`. Persisted knowledge facts are a future
  concern (the `knowledge_facts` table is ready for that).

  ## Arguments

    * `predicate` — `atom()` — the relation name (e.g. `:event_type`).
    * `arguments` — `[term()]` — the fact arguments (e.g. `[:evt, :deposit_received]`).

  ## Returns

    * `{atom(), [term()]}` — the fact tuple.

  ## Examples

      iex> Logistiki.Knowledge.assert_fact(:event_type, [:evt, :deposit_received])
      {:event_type, [:evt, :deposit_received]}
  """
  @doc since: "0.1.0"
  @spec assert_fact(atom(), [term()]) :: {atom(), [term()]}
  def assert_fact(predicate, arguments) when is_atom(predicate) and is_list(arguments) do
    {predicate, arguments}
  end

  @doc """
  Returns the rule categories used by Logistiki.

  ## Returns

    * `keyword()` — see `Logistiki.Knowledge.Rules.categories/0`.

  ## Examples

      iex> Logistiki.Knowledge.rule_categories()
      [
        business_rules: "Datalog-backed: should the event be processed / blocked / approved?",
        ...
      ]
  """
  @doc since: "0.1.0"
  @spec rule_categories() :: keyword()
  def rule_categories do
    Logistiki.Knowledge.Rules.categories()
  end
end
