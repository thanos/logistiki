defmodule Logistiki.Ledger do
  @moduledoc """
  The context for ledger backends.

  The runtime calls the configured backend (see `config :logistiki,
  :ledger_backend`) to execute journals, reverse them, and compute
  projections. Backends implement `Logistiki.Ledger.Behaviour`.
  """

  @doc "Returns the configured ledger backend module."
  def backend do
    Application.get_env(:logistiki, :ledger_backend, Logistiki.Ledger.Simulation)
  end

  @doc "Sets the ledger backend at runtime (mainly for tests)."
  def put_backend(module) when is_atom(module) do
    Application.put_env(:logistiki, :ledger_backend, module)
  end

  @doc "Executes a journal through the configured backend."
  def execute_journal(journal, opts \\ []) do
    backend().execute_journal(journal, opts)
  end

  @doc "Reverses a journal through the configured backend."
  def reverse_journal(journal, attrs \\ %{}, opts \\ []) do
    backend().reverse_journal(journal, attrs, opts)
  end

  @doc "Computes a balance through the configured backend."
  def balance(account, opts \\ []) do
    backend().balance(account, opts)
  end

  @doc "Computes a statement through the configured backend."
  def statement(account, opts \\ []) do
    backend().statement(account, opts)
  end

  @doc "Computes a trial balance through the configured backend."
  def trial_balance(opts \\ []) do
    backend().trial_balance(opts)
  end

  @doc "Returns the list of available backends."
  def backends do
    [Logistiki.Ledger.Simulation, Logistiki.Ledger.Beancount]
  end
end
