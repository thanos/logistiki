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

  The event is normalized, Datalog facts are generated, business rules are
  evaluated, an accounting policy is selected, a posting template is resolved,
  a journal is built and validated, the ledger backend executes it, projections
  are updated, and audit evidence is recorded. Every stage is emitted as
  telemetry and recorded in the audit trail.

  ## Arguments

    * `event` — a business event struct implementing `Logistiki.Event`
      (e.g. `%Logistiki.Event.DepositReceived{}`, `%Logistiki.Event.FeeAssessed{}`).

    * `opts` — `keyword()` of options:
        * `:currency` — `String.t` — filter projections to a currency (e.g. `"USD"`)

  ## Returns

    * `{:ok, %Logistiki.Accounting.Result{}}` — the pipeline succeeded.
      A result with `journal: nil` is valid (an event with no accounting impact).

    * `{:error, %Logistiki.Error{}}` — the pipeline rejected the event.

  ## Examples

      iex> event = %Logistiki.Event.DepositReceived{
      ...>   id: "evt_001",
      ...>   entity_type: "corporate",
      ...>   account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
      ...>   cash_account_code: "ASSETS:CASH:USD:NOSTRO",
      ...>   amount: Decimal.new("1000.00"),
      ...>   currency: "USD",
      ...>   effective_date: ~D[2026-07-07]
      ...> }
      iex> {:ok, result} = Logistiki.process(event)
      iex> result.policy
      :cash_deposit
      iex> result.journal.status
      "posted"

      iex> event = %Logistiki.Event.AccountOpened{id: "evt_002", account_code: "LIAB:ACME"}
      iex> {:ok, result} = Logistiki.process(event)
      iex> result.journal
      nil

      iex> {:error, %Logistiki.Error{code: :blocked_event}} = Logistiki.process(blocked_event)
  """
  @doc since: "0.1.0"
  @spec process(struct(), keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def process(event, opts \\ []) do
    Pipeline.run(event, opts)
  end

  @doc """
  Computes the balance(s) for an account.

  Aggregates descendant postings when `account_or_code` is a parent account,
  using the closure table for fast subtree queries.

  ## Arguments

    * `account_or_code` — one of:
        * `%Logistiki.VirtualAccounts.VirtualAccount{}` — the account struct
        * `String.t` — an account code (e.g. `"ASSETS:CASH:USD:NOSTRO"`) or id
        * `integer()` — an account id

    * `opts` — `keyword()` of options:
        * `:currency` — `String.t` — filter to a single currency (e.g. `"USD"`)

  ## Returns

    * `{:ok, [Logistiki.Projections.Balance.t()]}` — one balance per currency.
    * `{:error, :account_not_found}` — the account does not exist.

  ## Examples

      iex> {:ok, [balance]} = Logistiki.balance("ASSETS:CASH:USD:NOSTRO")
      iex> balance.net
      Decimal.new("1000.00")

      iex> {:ok, balances} = Logistiki.balance("LIABILITIES:CLIENT_DEPOSITS:USD:ACME")
      iex> Enum.reduce(balances, Decimal.new(0), &Decimal.add(&1.net, &2.net))
      Decimal.new("-1000.00")

      iex> {:error, :account_not_found} = Logistiki.balance("UNKNOWN:CODE")
  """
  @doc since: "0.1.0"
  @spec balance(VirtualAccount.t() | String.t() | integer(), keyword()) ::
          {:ok, [Logistiki.Projections.Balance.t()]} | {:error, term()}
  def balance(account_or_code, opts \\ []) do
    Ledger.balance(account_or_code, opts)
  end

  @doc """
  Computes balances for accounts linked to `entity`.

  Uses the `entity_accounts` relationship table to find all accounts owned by
  (or otherwise linked to) the entity, then sums postings across them.

  ## Arguments

    * `entity` — `%Logistiki.BusinessEntities.BusinessEntity{}` or entity id.
    * `opts` — `keyword()` of options:
        * `:currency` — `String.t` — filter to a currency (e.g. `"USD"`)
        * `:relationship_type` — `atom()` — filter by type (e.g. `:owner`)
        * `:at` — `Date.t` — effective date for temporal filtering

  ## Returns

    * `{:ok, [Logistiki.Projections.Balance.t()]}` — balances per currency.

  ## Examples

      iex> {:ok, balances} = Logistiki.balance_for_entity(acme_entity)
      iex> hd(balances).net
      Decimal.new("-1000.00")

      iex> {:ok, balances} = Logistiki.balance_for_entity(acme_entity, relationship_type: :owner)
  """
  @doc since: "0.1.0"
  @spec balance_for_entity(BusinessEntity.t() | integer(), keyword()) ::
          {:ok, [Logistiki.Projections.Balance.t()]}
  def balance_for_entity(entity, opts \\ []) do
    Projections.balance_for_entity(entity, opts)
  end

  @doc """
  Computes balances for accounts linked to `entity` or any of its descendants.

  Uses the business-entity closure table to find all descendant entities, then
  finds all accounts linked to any of them, and sums postings across the set.

  ## Arguments

    * `entity` — `%Logistiki.BusinessEntities.BusinessEntity{}` or entity id.
    * `opts` — `keyword()` of options:
        * `:currency` — `String.t` — filter to a currency
        * `:relationship_type` — `atom()` — filter by type
        * `:at` — `Date.t` — effective date

  ## Returns

    * `{:ok, [Logistiki.Projections.Balance.t()]}` — balances per currency.

  ## Examples

      iex> {:ok, balances} = Logistiki.balance_for_entity_tree(acme_holdings)
      iex> Enum.reduce(balances, Decimal.new(0), &Decimal.add(&1.net, &2.net))
      Decimal.new("-1500.00")
  """
  @doc since: "0.1.0"
  @spec balance_for_entity_tree(BusinessEntity.t() | integer(), keyword()) ::
          {:ok, [Logistiki.Projections.Balance.t()]}
  def balance_for_entity_tree(entity, opts \\ []) do
    Projections.balance_for_entity_tree(entity, opts)
  end

  @doc """
  Builds a running-balance statement for an account.

  Returns ordered statement lines (by effective date, journal insertion, then
  posting sequence) each carrying a running balance per currency.

  ## Arguments

    * `account_or_code` — `%VirtualAccount{}`, account code (`String.t`), or id (`integer()`).
    * `opts` — `keyword()` of options:
        * `:currency` — `String.t` — filter to a currency

  ## Returns

    * `{:ok, [Logistiki.Projections.StatementLine.t()]}` — ordered lines.
    * `{:error, :account_not_found}` — the account does not exist.

  ## Examples

      iex> {:ok, lines} = Logistiki.statement("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")
      iex> hd(lines).running_balance
      Decimal.new("-1000.00")
      iex> hd(lines).selected_policy
      "cash_deposit"
  """
  @doc since: "0.1.0"
  @spec statement(VirtualAccount.t() | String.t() | integer(), keyword()) ::
          {:ok, [Logistiki.Projections.StatementLine.t()]} | {:error, term()}
  def statement(account_or_code, opts \\ []) do
    Ledger.statement(account_or_code, opts)
  end

  @doc """
  Builds a trial balance across all posted and reversed journals.

  Returns debit/credit totals per account per currency. Debits and credits must
  balance per currency (`balanced` flag).

  ## Arguments

    * `opts` — `keyword()` of options:
        * `:currency` — `String.t` — filter to a currency

  ## Returns

    * `{:ok, %Logistiki.Projections.TrialBalance{}}` — with `lines`, `currencies`, `balanced`.

  ## Examples

      iex> {:ok, tb} = Logistiki.trial_balance()
      iex> tb.balanced
      true
      iex> tb.currencies
      ["USD"]
      iex> hd(tb.lines).account_code
      "ASSETS:CASH:USD:NOSTRO"
  """
  @doc since: "0.1.0"
  @spec trial_balance(keyword()) :: {:ok, Logistiki.Projections.TrialBalance.t()}
  def trial_balance(opts \\ []) do
    Ledger.trial_balance(opts)
  end

  @doc """
  Builds a general ledger view of all posted and reversed postings.

  Returns all postings ordered by effective date, journal insertion, then
  posting sequence.

  ## Arguments

    * `opts` — `keyword()` of options:
        * `:currency` — `String.t` — filter to a currency

  ## Returns

    * `%Logistiki.Projections.GeneralLedger{}` — with `lines`.

  ## Examples

      iex> gl = Logistiki.general_ledger()
      iex> length(gl.lines)
      4
      iex> hd(gl.lines).account_code
      "ASSETS:CASH:USD:NOSTRO"
  """
  @doc since: "0.1.0"
  @spec general_ledger(keyword()) :: Logistiki.Projections.GeneralLedger.t()
  def general_ledger(opts \\ []) do
    Projections.general_ledger(opts)
  end

  @doc """
  Builds a balance sheet (assets, liabilities, equity).

  ## Arguments

    * `opts` — `keyword()` of options:
        * `:currency` — `String.t` — filter to a currency

  ## Returns

    * `%Logistiki.Projections.BalanceSheet{}` — with `assets`, `liabilities`,
      `equity` sections (each with `balances` and `totals_by_currency`), and
      `totals_by_currency`.

  ## Examples

      iex> bs = Logistiki.balance_sheet()
      iex> bs.totals_by_currency["USD"][:assets]
      Decimal.new("1000.00")
      iex> bs.totals_by_currency["USD"][:liabilities]
      Decimal.new("-1000.00")
  """
  @doc since: "0.1.0"
  @spec balance_sheet(keyword()) :: Logistiki.Projections.BalanceSheet.t()
  def balance_sheet(opts \\ []) do
    Projections.balance_sheet(opts)
  end

  @doc """
  Builds an income statement (income, expenses, net profit).

  ## Arguments

    * `opts` — `keyword()` of options:
        * `:currency` — `String.t` — filter to a currency

  ## Returns

    * `%Logistiki.Projections.IncomeStatement{}` — with `income`, `expenses`
      sections and `net_profit_by_currency`.

  ## Examples

      iex> is = Logistiki.income_statement()
      iex> is.net_profit_by_currency["USD"]
      Decimal.new("-25.00")
  """
  @doc since: "0.1.0"
  @spec income_statement(keyword()) :: Logistiki.Projections.IncomeStatement.t()
  def income_statement(opts \\ []) do
    Projections.income_statement(opts)
  end

  @doc """
  Returns the configured ledger backend module.

  ## Returns

    * `module()` — e.g. `Logistiki.Ledger.Simulation` or `Logistiki.Ledger.Beancount`.

  ## Examples

      iex> Logistiki.ledger_backend()
      Logistiki.Ledger.Simulation
  """
  @doc since: "0.1.0"
  @spec ledger_backend() :: module()
  def ledger_backend, do: Ledger.backend()

  @doc """
  Sets the ledger backend at runtime (mainly for tests and demos).

  ## Arguments

    * `module` — `module()` — a module implementing `Logistiki.Ledger.Behaviour`
      (e.g. `Logistiki.Ledger.Beancount`).

  ## Examples

      iex> Logistiki.put_ledger_backend(Logistiki.Ledger.Beancount)
      :ok
      iex> Logistiki.ledger_backend()
      Logistiki.Ledger.Beancount
  """
  @doc since: "0.1.0"
  @spec put_ledger_backend(module()) :: :ok
  def put_ledger_backend(module), do: Ledger.put_backend(module)

  @doc """
  Returns the `Logistiki.Error` struct module (for documentation/introspection).

  ## Examples

      iex> Logistiki.error()
      Logistiki.Error
  """
  @doc since: "0.1.0"
  @spec error() :: module()
  def error, do: Error

  @doc """
  Returns the `Logistiki.Accounting.Result` struct module (for documentation/introspection).

  ## Examples

      iex> Logistiki.result()
      Logistiki.Accounting.Result
  """
  @doc since: "0.1.0"
  @spec result() :: module()
  def result, do: Result
end
