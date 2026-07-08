defmodule Logistiki.Ledger do
  @moduledoc """
  The context for ledger backends.

  The runtime calls the configured backend (see `config :logistiki,
  :ledger_backend`) to execute journals, reverse them, and compute
  projections. Backends implement `Logistiki.Ledger.Behaviour`.
  """

  @doc """
  Returns the configured ledger backend module.

  ## Returns

    * `module()` — e.g. `Logistiki.Ledger.Simulation` or
      `Logistiki.Ledger.Beancount`.

  ## Examples

      iex> Logistiki.Ledger.backend()
      Logistiki.Ledger.Simulation
  """
  @doc since: "0.1.0"
  @spec backend() :: module()
  def backend do
    Application.get_env(:logistiki, :ledger_backend, Logistiki.Ledger.Simulation)
  end

  @doc """
  Sets the ledger backend at runtime (mainly for tests).

  ## Arguments

    * `module` — `module()` — a module implementing
      `Logistiki.Ledger.Behaviour` (e.g. `Logistiki.Ledger.Beancount`).

  ## Examples

      iex> Logistiki.Ledger.put_backend(Logistiki.Ledger.Beancount)
      :ok
  """
  @doc since: "0.1.0"
  @spec put_backend(module()) :: :ok
  def put_backend(module) when is_atom(module) do
    Application.put_env(:logistiki, :ledger_backend, module)
  end

  @doc """
  Executes a journal through the configured backend.

  ## Arguments

    * `journal` — `Journal.t()` — the draft journal with postings attached.
    * `opts` — `keyword()` — backend-specific options (e.g. `[currency: "USD"]`).

  ## Returns

    * `{:ok, Logistiki.Ledger.Result.t()}` — the backend result.
    * `{:error, term()}` — execution failed.

  ## Examples

      iex> {:ok, result} = Logistiki.Ledger.execute_journal(journal)
      iex> result.status
      :ok
  """
  @doc since: "0.1.0"
  @spec execute_journal(Logistiki.Accounting.Journal.t(), keyword()) ::
          {:ok, Logistiki.Ledger.Result.t()} | {:error, term()}
  def execute_journal(journal, opts \\ []) do
    backend().execute_journal(journal, opts)
  end

  @doc """
  Reverses a journal through the configured backend.

  ## Arguments

    * `journal` — `Journal.t()` — the posted journal to reverse.
    * `attrs` — `map()` — reversal attributes (e.g. `%{reason: "mistaken fee"}`).
    * `opts` — `keyword()` — backend-specific options.

  ## Returns

    * `{:ok, Logistiki.Ledger.Result.t()}` — the reversal result.
    * `{:error, term()}` — reversal failed.

  ## Examples

      iex> {:ok, result} = Logistiki.Ledger.reverse_journal(journal, %{reason: "mistaken fee"})
      iex> result.status
      :ok
  """
  @doc since: "0.1.0"
  @spec reverse_journal(Logistiki.Accounting.Journal.t(), map(), keyword()) ::
          {:ok, Logistiki.Ledger.Result.t()} | {:error, term()}
  def reverse_journal(journal, attrs \\ %{}, opts \\ []) do
    backend().reverse_journal(journal, attrs, opts)
  end

  @doc """
  Computes a balance through the configured backend.

  ## Arguments

    * `account` — `VirtualAccount.t() | String.t() | integer()` — account
      struct, code, or id.
    * `opts` — `keyword()` — e.g. `[currency: "USD"]`.

  ## Returns

    * `{:ok, [Logistiki.Projections.Balance.t()]}` — balances per currency.

  ## Examples

      iex> {:ok, [balance]} = Logistiki.Ledger.balance("ASSETS:CASH:USD:NOSTRO")
      iex> balance.net
      Decimal.new("1000.00")
  """
  @doc since: "0.1.0"
  @spec balance(Logistiki.VirtualAccounts.VirtualAccount.t() | String.t() | integer(), keyword()) ::
          {:ok, [Logistiki.Projections.Balance.t()]} | {:error, term()}
  def balance(account, opts \\ []) do
    backend().balance(account, opts)
  end

  @doc """
  Computes a statement through the configured backend.

  ## Arguments

    * `account` — `VirtualAccount.t() | String.t() | integer()`.
    * `opts` — `keyword()` — e.g. `[currency: "USD"]`.

  ## Returns

    * `{:ok, [Logistiki.Projections.StatementLine.t()]}` — ordered lines.

  ## Examples

      iex> {:ok, lines} = Logistiki.Ledger.statement("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")
      iex> hd(lines).running_balance
      Decimal.new("-1000.00")
  """
  @doc since: "0.1.0"
  @spec statement(Logistiki.VirtualAccounts.VirtualAccount.t() | String.t() | integer(), keyword()) ::
          {:ok, [Logistiki.Projections.StatementLine.t()]} | {:error, term()}
  def statement(account, opts \\ []) do
    backend().statement(account, opts)
  end

  @doc """
  Computes a trial balance through the configured backend.

  ## Arguments

    * `opts` — `keyword()` — e.g. `[currency: "USD"]`.

  ## Returns

    * `{:ok, Logistiki.Projections.TrialBalance.t()}` — with `lines`,
      `currencies`, `balanced`.

  ## Examples

      iex> {:ok, tb} = Logistiki.Ledger.trial_balance()
      iex> tb.balanced
      true
  """
  @doc since: "0.1.0"
  @spec trial_balance(keyword()) :: {:ok, Logistiki.Projections.TrialBalance.t()}
  def trial_balance(opts \\ []) do
    backend().trial_balance(opts)
  end

  @doc """
  Returns the list of available backends.

  ## Returns

    * `[module()]` — `[Logistiki.Ledger.Simulation, Logistiki.Ledger.Beancount]`.

  ## Examples

      iex> Logistiki.Ledger.backends()
      [Logistiki.Ledger.Simulation, Logistiki.Ledger.Beancount]
  """
  @doc since: "0.1.0"
  @spec backends() :: [module(), ...]
  def backends do
    [Logistiki.Ledger.Simulation, Logistiki.Ledger.Beancount]
  end
end
