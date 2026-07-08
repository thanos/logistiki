defmodule Logistiki.Projections.ProjectionEngine do
  @moduledoc """
  Computes projections over immutable postings.

  Balances are never authoritative stored state; they are derived here. The
  simulation backend delegates to this engine. The Beancount backend uses
  `beancount_ex` as the oracle and its results are compared against this
  engine's.

  ## Supported projections

    * `balance/2` — leaf or parent account (aggregates descendants)
    * `balance_for_entity/2` — accounts linked to an entity
    * `balance_for_entity_tree/2` — accounts linked to an entity subtree
    * `statement/2` — running-balance statement lines
    * `trial_balance/1` — debit/credit totals per account per currency
    * `general_ledger/1` — all postings ordered
    * `balance_sheet/1`, `income_statement/1` — sectioned views
  """

  import Ecto.Query

  alias Logistiki.Accounting.{Journal, Posting}
  alias Logistiki.Projections.{Balance, BalanceSheet, GeneralLedger, IncomeStatement, StatementLine, TrialBalance}
  alias Logistiki.Relationships
  alias Logistiki.Repo
  alias Logistiki.VirtualAccounts
  alias Logistiki.VirtualAccounts.VirtualAccount

  # ------------------------------------------------------------------
  # Balance
  # ------------------------------------------------------------------

  @doc "Computes the balance(s) for `account` (a struct, id, or code). Aggregates descendants for parent accounts."
  def balance(account, opts \\ [])

  def balance(%VirtualAccount{} = account, opts), do: balance_for_account(account, opts)

  def balance(code, opts) when is_binary(code) do
    with {:ok, account} <- VirtualAccounts.resolve(code), do: balance_for_account(account, opts)
  end

  def balance(account_id, opts) do
    case VirtualAccounts.get_account(account_id) do
      {:ok, account} -> balance_for_account(account, opts)
      {:error, _} -> {:error, :account_not_found}
    end
  end

  defp balance_for_account(%VirtualAccount{id: id} = account, opts) do
    currency = Keyword.get(opts, :currency)
    account_ids = VirtualAccounts.descendant_ids(account)
    {:ok, balances_for_account_ids(account_ids, currency, id)}
  end

  @doc "Computes balances for accounts linked to `entity`."
  def balance_for_entity(entity, opts \\ []) do
    accounts = Relationships.list_accounts_for_entity(entity, opts)
    account_ids = Enum.map(accounts, & &1.id)
    currency = Keyword.get(opts, :currency)
    {:ok, balances_for_account_ids(account_ids, currency, nil)}
  end

  @doc "Computes balances for accounts linked to `entity` or any of its descendants."
  def balance_for_entity_tree(entity, opts \\ []) do
    accounts = Relationships.list_accounts_for_entity_tree(entity, opts)
    account_ids = Enum.map(accounts, & &1.id)
    currency = Keyword.get(opts, :currency)
    {:ok, balances_for_account_ids(account_ids, currency, nil)}
  end

  defp balances_for_account_ids([], _currency, _owner_id), do: []

  defp balances_for_account_ids(account_ids, currency, owner_id) do
    rows =
      from(p in Posting,
        join: j in Journal, on: j.id == p.journal_id,
        where: j.status in ["posted", "reversed"] and p.virtual_account_id in ^account_ids,
        group_by: [p.account_code, p.currency, p.debit_credit],
        select: %{
          account_code: p.account_code,
          currency: p.currency,
          debit_credit: p.debit_credit,
          total: sum(p.amount),
          count: count(p.id)
        }
      )
      |> maybe_filter_currency(currency)
      |> Repo.all()

    rows
    |> Enum.group_by(fn r -> {r.account_code, r.currency} end)
    |> Enum.map(fn {{account_code, cur}, group} ->
      {debits, credits, count} = debit_credit_totals_with_count(group)
      Balance.build(account_code, cur, debits, credits, count)
      |> Map.put(:account_id, owner_id)
    end)
    |> Enum.sort_by(fn b -> {b.currency, b.account_code} end)
  end

  defp debit_credit_totals_with_count(group) do
    Enum.reduce(group, {Decimal.new(0), Decimal.new(0), 0}, fn r, {d, c, n} ->
      if r.debit_credit == "debit",
        do: {Decimal.add(d, r.total || Decimal.new(0)), c, n + r.count},
        else: {d, Decimal.add(c, r.total || Decimal.new(0)), n + r.count}
    end)
  end

  defp debit_credit_totals(group) do
    Enum.reduce(group, {Decimal.new(0), Decimal.new(0)}, fn r, {d, c} ->
      if r.debit_credit == "debit",
        do: {Decimal.add(d, r.total || Decimal.new(0)), c},
        else: {d, Decimal.add(c, r.total || Decimal.new(0))}
    end)
  end

  # ------------------------------------------------------------------
  # Statement
  # ------------------------------------------------------------------

  @doc "Builds a running-balance statement for `account` (aggregates descendant postings)."
  def statement(account, opts \\ [])

  def statement(%VirtualAccount{} = account, opts), do: statement_for_account(account, opts)

  def statement(code, opts) when is_binary(code) do
    with {:ok, account} <- VirtualAccounts.resolve(code), do: statement_for_account(account, opts)
  end

  defp statement_for_account(%VirtualAccount{} = account, opts) do
    currency = Keyword.get(opts, :currency)
    account_ids = VirtualAccounts.descendant_ids(account)

    rows =
      from(p in Posting,
        join: j in Journal, on: j.id == p.journal_id,
        where: j.status in ["posted", "reversed"] and p.virtual_account_id in ^account_ids,
        order_by: [asc: j.effective_date, asc: j.inserted_at, asc: p.sequence],
        select: %{
          posting_id: p.id,
          journal_id: j.id,
          event_id: j.event_id,
          date: j.effective_date,
          description: j.description,
          account_code: p.account_code,
          debit_credit: p.debit_credit,
          amount: p.amount,
          currency: p.currency,
          source_system: j.source_system,
          source_id: j.source_id,
          selected_policy: j.selected_policy,
          selected_template: j.selected_template,
          metadata: p.metadata
        }
      )
      |> maybe_filter_currency(currency)
      |> Repo.all()
      |> attach_running_balance()

    {:ok, rows}
  end

  defp attach_running_balance(rows) do
    {lines, _running} =
      Enum.map_reduce(rows, %{}, fn row, running ->
        signed = signed_amount(row.debit_credit, row.amount)
        new_running = Map.update(running, row.currency, signed, &Decimal.add(&1, signed))

        line = %StatementLine{
          journal_id: row.journal_id,
          posting_id: row.posting_id,
          event_id: row.event_id,
          date: row.date,
          description: row.description,
          account_code: row.account_code,
          debit: if(row.debit_credit == "debit", do: row.amount, else: nil),
          credit: if(row.debit_credit == "credit", do: row.amount, else: nil),
          amount: signed,
          currency: row.currency,
          running_balance: Map.get(new_running, row.currency),
          source_system: row.source_system,
          source_id: row.source_id,
          selected_policy: row.selected_policy,
          selected_template: row.selected_template,
          metadata: row.metadata || %{}
        }

        {line, new_running}
      end)

    lines
  end

  defp signed_amount("debit", amount), do: amount
  defp signed_amount("credit", amount), do: Decimal.negate(amount)

  # ------------------------------------------------------------------
  # Trial balance
  # ------------------------------------------------------------------

  @doc "Builds a trial balance across all posted journals."
  def trial_balance(opts \\ []) do
    currency = Keyword.get(opts, :currency)

    rows =
      from(p in Posting,
        join: j in Journal, on: j.id == p.journal_id,
        left_join: a in VirtualAccount, on: a.id == p.virtual_account_id,
        where: j.status in ["posted", "reversed"],
        group_by: [p.account_code, a.name, p.currency, p.debit_credit],
        order_by: [asc: p.currency, asc: p.account_code],
        select: %{
          account_code: p.account_code,
          account_name: a.name,
          currency: p.currency,
          debit_credit: p.debit_credit,
          total: sum(p.amount)
        }
      )
      |> maybe_filter_currency(currency)
      |> Repo.all()

    lines =
      rows
      |> Enum.group_by(fn r -> {r.account_code, r.account_name, r.currency} end)
      |> Enum.map(fn {{account_code, account_name, cur}, group} ->
        {debits, credits} = debit_credit_totals(group)

        %{
          account_code: account_code,
          account_name: account_name,
          debit_total: debits,
          credit_total: credits,
          net: Decimal.sub(debits, credits),
          currency: cur
        }
      end)
      |> Enum.sort_by(fn l -> {l.currency, l.account_code} end)

    currencies = lines |> Enum.map(& &1.currency) |> Enum.uniq()

    balanced? =
      Enum.all?(currencies, fn cur ->
        cur_lines = Enum.filter(lines, &(&1.currency == cur))
        debits = cur_lines |> Enum.map(& &1.debit_total) |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
        credits = cur_lines |> Enum.map(& &1.credit_total) |> Enum.reduce(Decimal.new(0), &Decimal.add/2)
        Decimal.equal?(debits, credits)
      end)

    %TrialBalance{lines: lines, currencies: currencies, balanced: balanced?}
  end

  # ------------------------------------------------------------------
  # General ledger
  # ------------------------------------------------------------------

  @doc "Builds a general ledger view of all posted postings."
  def general_ledger(opts \\ []) do
    currency = Keyword.get(opts, :currency)

    rows =
      from(p in Posting,
        join: j in Journal, on: j.id == p.journal_id,
        where: j.status in ["posted", "reversed"],
        order_by: [asc: j.effective_date, asc: j.inserted_at, asc: p.sequence],
        select: %{
          posting_id: p.id,
          journal_id: j.id,
          event_id: j.event_id,
          date: j.effective_date,
          description: j.description,
          account_code: p.account_code,
          debit_credit: p.debit_credit,
          amount: p.amount,
          currency: p.currency,
          source_system: j.source_system,
          source_id: j.source_id,
          selected_policy: j.selected_policy,
          selected_template: j.selected_template,
          metadata: p.metadata
        }
      )
      |> maybe_filter_currency(currency)
      |> Repo.all()

    lines =
      Enum.map(rows, fn row ->
        %StatementLine{
          journal_id: row.journal_id,
          posting_id: row.posting_id,
          event_id: row.event_id,
          date: row.date,
          description: row.description,
          account_code: row.account_code,
          debit: if(row.debit_credit == "debit", do: row.amount, else: nil),
          credit: if(row.debit_credit == "credit", do: row.amount, else: nil),
          amount: signed_amount(row.debit_credit, row.amount),
          currency: row.currency,
          running_balance: nil,
          source_system: row.source_system,
          source_id: row.source_id,
          selected_policy: row.selected_policy,
          selected_template: row.selected_template,
          metadata: row.metadata || %{}
        }
      end)

    %GeneralLedger{lines: lines}
  end

  # ------------------------------------------------------------------
  # Balance sheet / income statement
  # ------------------------------------------------------------------

  # Maps a Logistiki account type to a financial-statement section.
  @section_by_type %{
    "asset" => :assets,
    "settlement" => :assets,
    "liability" => :liabilities,
    "client" => :liabilities,
    "suspense" => :liabilities,
    "clearing" => :liabilities,
    "tax" => :liabilities,
    "equity" => :equity,
    "income" => :income,
    "fee" => :income,
    "expense" => :expenses
  }

  @doc "Builds a balance sheet (assets, liabilities, equity)."
  def balance_sheet(opts \\ []) do
    sections = section_balances(~w(asset settlement liability client suspense clearing tax equity)a, opts)

    %BalanceSheet{
      assets: section(sections[:assets]),
      liabilities: section(sections[:liabilities]),
      equity: section(sections[:equity]),
      totals_by_currency: section_totals(sections)
    }
  end

  @doc "Builds an income statement (income, expenses, net profit)."
  def income_statement(opts \\ []) do
    sections = section_balances(~w(income fee expense)a, opts)

    income = section(sections[:income])
    expenses = section(sections[:expenses])

    net_profit_by_currency =
      Enum.reduce(Map.keys(income.totals_by_currency) ++ Map.keys(expenses.totals_by_currency), %{}, fn cur, acc ->
        inc = Map.get(income.totals_by_currency, cur, Decimal.new(0))
        exp = Map.get(expenses.totals_by_currency, cur, Decimal.new(0))
        Map.put(acc, cur, Decimal.sub(inc, exp))
      end)

    %IncomeStatement{income: income, expenses: expenses, net_profit_by_currency: net_profit_by_currency}
  end

  defp section_balances(types, opts) do
    currency = Keyword.get(opts, :currency)
    type_strings = Enum.map(types, &Atom.to_string/1)

    rows =
      from(p in Posting,
        join: j in Journal, on: j.id == p.journal_id,
        join: a in VirtualAccount, on: a.id == p.virtual_account_id,
        where: j.status in ["posted", "reversed"] and a.account_type in ^type_strings,
        group_by: [a.id, a.code, a.account_type, p.currency, p.debit_credit],
        select: %{
          account_id: a.id,
          account_code: a.code,
          account_type: a.account_type,
          currency: p.currency,
          debit_credit: p.debit_credit,
          total: sum(p.amount)
        }
      )
      |> maybe_filter_currency(currency)
      |> Repo.all()

    by_account =
      Enum.reduce(rows, %{}, fn row, acc ->
        key = {row.account_id, row.account_code, row.account_type, row.currency}
        entry = Map.get(acc, key, %{debit: Decimal.new(0), credit: Decimal.new(0)})

        entry =
          if row.debit_credit == "debit",
            do: %{entry | debit: Decimal.add(entry.debit, row.total || Decimal.new(0))},
            else: %{entry | credit: Decimal.add(entry.credit, row.total || Decimal.new(0))}

        Map.put(acc, key, entry)
      end)

    by_account
    |> Enum.map(fn {{_id, code, type, cur}, entry} ->
      balance = %Balance{
        account_id: nil,
        account_code: code,
        currency: cur,
        debit_total: entry.debit,
        credit_total: entry.credit,
        net: Decimal.sub(entry.debit, entry.credit),
        posting_count: nil
      }

      {Map.fetch!(@section_by_type, type), balance}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp section(nil), do: %{balances: [], totals_by_currency: %{}}

  defp section(balances) do
    totals_by_currency =
      Enum.reduce(balances, %{}, fn b, acc ->
        Map.update(acc, b.currency, b.net, &Decimal.add(&1, b.net))
      end)

    %{
      balances: Enum.sort_by(balances, & &1.account_code),
      totals_by_currency: totals_by_currency
    }
  end

  defp section_totals(sections) do
    Enum.reduce(sections, %{}, fn {section_key, balances}, acc ->
      Enum.reduce(balances, acc, fn b, a ->
        cur_map = Map.get(a, b.currency, %{})
        Map.put(a, b.currency, Map.put(cur_map, section_key, Decimal.add(Map.get(cur_map, section_key, Decimal.new(0)), b.net)))
      end)
    end)
  end

  defp maybe_filter_currency(query, nil), do: query
  defp maybe_filter_currency(query, currency), do: where(query, [p], p.currency == ^currency)
end
