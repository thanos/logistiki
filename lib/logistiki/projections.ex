defmodule Logistiki.Projections do
  @moduledoc """
  The context for projections.

  Balances are never authoritative stored state; they are projections over
  immutable postings. This module delegates to
  `Logistiki.Projections.ProjectionEngine` (used by the simulation backend) so
  callers can compute projections regardless of the configured ledger backend.
  """

  alias Logistiki.Projections.ProjectionEngine

  @doc "Computes balance(s) for an account (struct, id, or code). Aggregates descendants."
  @doc since: "0.1.0"
  def balance(account, opts \\ []), do: ProjectionEngine.balance(account, opts)

  @doc "Computes balances for accounts linked to an entity."
  @doc since: "0.1.0"
  def balance_for_entity(entity, opts \\ []), do: ProjectionEngine.balance_for_entity(entity, opts)

  @doc "Computes balances for accounts linked to an entity subtree."
  @doc since: "0.1.0"
  def balance_for_entity_tree(entity, opts \\ []),
    do: ProjectionEngine.balance_for_entity_tree(entity, opts)

  @doc "Builds a running-balance statement for an account."
  @doc since: "0.1.0"
  def statement(account, opts \\ []), do: ProjectionEngine.statement(account, opts)

  @doc "Builds a trial balance."
  @doc since: "0.1.0"
  def trial_balance(opts \\ []), do: ProjectionEngine.trial_balance(opts)

  @doc "Builds a general ledger view."
  @doc since: "0.1.0"
  def general_ledger(opts \\ []), do: ProjectionEngine.general_ledger(opts)

  @doc "Builds a balance sheet."
  @doc since: "0.1.0"
  def balance_sheet(opts \\ []), do: ProjectionEngine.balance_sheet(opts)

  @doc "Builds an income statement."
  @doc since: "0.1.0"
  def income_statement(opts \\ []), do: ProjectionEngine.income_statement(opts)
end
