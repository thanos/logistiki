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

  @doc "Returns the configured knowledge program module (default `Logistiki.Knowledge.Program`)."
  def load_program do
    Application.get_env(:logistiki, :knowledge_program, Logistiki.Knowledge.Program)
  end

  @doc "Evaluates the knowledge program for `normalized_event`."
  def evaluate(normalized_event, opts \\ []) do
    KnowledgeBase.evaluate(normalized_event, opts)
  end

  @doc "Materializes the program and returns raw `ExDatalog.Knowledge`."
  def materialize(normalized_event, opts \\ []) do
    KnowledgeBase.materialize_for(normalized_event, opts)
  end

  @doc """
  Asserts a runtime fact to be added to the next materialization.

  In v0.1.0 this is a convenience that returns the fact tuple for use with
  `Logistiki.Knowledge.KnowledgeBase`. Persisted knowledge facts are a future
  concern (the `knowledge_facts` table is ready for that).
  """
  def assert_fact(predicate, arguments) when is_atom(predicate) and is_list(arguments) do
    {predicate, arguments}
  end

  @doc "Returns the rule categories used by Logistiki."
  def rule_categories do
    Logistiki.Knowledge.Rules.categories()
  end
end
