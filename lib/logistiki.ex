defmodule Logistiki do
  @moduledoc """
  Logistiki — an embedded OTP accounting engine for Elixir applications.

  Logistiki is the accounting execution layer that applications embed. It is
  not a bank, an ERP, a payment system, or a compliance platform.

  ## The primary API

  Applications publish **business events**:

      Logistiki.process(%Logistiki.Event.DepositReceived{...})

  Logistiki decides whether and how those events become accounting entries.
  Applications should **not** directly create journals or postings as their
  normal workflow — those are internal accounting artifacts.

  ## Querying the results

      Logistiki.balance(account)
      Logistiki.statement(account)
      Logistiki.trial_balance()
      Logistiki.general_ledger()
      Logistiki.balance_sheet()
      Logistiki.income_statement()

  Balances are projections over immutable postings — never the source of truth.

  ## Administrative API

  Lower-level functions live under explicit namespaces (`Logistiki.Accounting`,
  `Logistiki.BusinessEntities`, `Logistiki.VirtualAccounts`,
  `Logistiki.Relationships`, `Logistiki.Knowledge`, `Logistiki.Audit`).
  """

  alias Logistiki.Accounting.Pipeline
  alias Logistiki.Accounting.Result
  alias Logistiki.Error
  alias Logistiki.Ledger
  alias Logistiki.Projections

  @doc """
  Processes a business event through the full accounting pipeline.

  Returns `{:ok, %Logistiki.Accounting.Result{}}` or `{:error, %Logistiki.Error{}}`.
  A result with `journal: nil` is valid (e.g. an event with no accounting impact).
  """
  def process(event, opts \\ []) do
    Pipeline.run(event, opts)
  end

  @doc "Computes the balance(s) for `account_or_code` (a struct, id, or code)."
  def balance(account_or_code, opts \\ []) do
    Ledger.balance(account_or_code, opts)
  end

  @doc "Computes balances for accounts linked to `entity`."
  def balance_for_entity(entity, opts \\ []) do
    Projections.balance_for_entity(entity, opts)
  end

  @doc "Computes balances for accounts linked to `entity` or its descendants."
  def balance_for_entity_tree(entity, opts \\ []) do
    Projections.balance_for_entity_tree(entity, opts)
  end

  @doc "Builds a running-balance statement for `account_or_code`."
  def statement(account_or_code, opts \\ []) do
    Ledger.statement(account_or_code, opts)
  end

  @doc "Builds a trial balance across all posted journals."
  def trial_balance(opts \\ []) do
    Ledger.trial_balance(opts)
  end

  @doc "Builds a general ledger view."
  def general_ledger(opts \\ []) do
    Projections.general_ledger(opts)
  end

  @doc "Builds a balance sheet."
  def balance_sheet(opts \\ []) do
    Projections.balance_sheet(opts)
  end

  @doc "Builds an income statement."
  def income_statement(opts \\ []) do
    Projections.income_statement(opts)
  end

  @doc "Returns the configured ledger backend module."
  def ledger_backend, do: Ledger.backend()

  @doc "Sets the ledger backend at runtime (mainly for tests)."
  def put_ledger_backend(module), do: Ledger.put_backend(module)

  @doc "Returns the `%Logistiki.Error{}` struct module (for documentation)."
  def error, do: Error

  @doc "Returns the `%Logistiki.Accounting.Result{}` struct module (for documentation)."
  def result, do: Result
end
