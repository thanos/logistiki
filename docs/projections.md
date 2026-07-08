# Projections

**Balances are never authoritative stored state.** They are projections over
immutable postings, computed by `Logistiki.Projections.ProjectionEngine`.

## Balance

```elixir
Logistiki.balance(account_or_code, opts \\ [])
Logistiki.balance(parent_account)
Logistiki.balance_for_entity(entity)
Logistiki.balance_for_entity_tree(entity)
```

A `Logistiki.Projections.Balance` carries `debit_total`, `credit_total`, `net`
(`debit - credit`, signed), `currency`, and `posting_count`.

- **Parent balances aggregate descendants** — the query uses the
  `virtual_account_closure` table to sum postings across the subtree.
- **Entity balances aggregate linked accounts** — via `entity_accounts`.
- **Entity subtree balances aggregate across descendant entities** — via the
  `business_entity_closure` table joined to `entity_accounts`.

Balance-counted journals are those with `status in ["posted", "reversed"]`. A
reversed journal's postings still count because the reversal journal cancels
them; both remain balance-counted and net to zero.

## Statement

`Logistiki.statement(account, opts \\ [])` returns ordered
`Logistiki.Projections.StatementLine` structs with a running balance. Each line
includes `journal_id`, `posting_id`, `event_id`, `date`, `description`,
`account_code`, `debit`, `credit`, signed `amount`, `currency`,
`running_balance`, `source_system`, `source_id`, `selected_policy`,
`selected_template`, and `metadata`.

## Trial balance

`Logistiki.trial_balance(opts \\ [])` returns a `Logistiki.Projections.TrialBalance`
with debit/credit totals per account per currency. Debits and credits must
balance per currency (`balanced` flag).

## General ledger

`Logistiki.general_ledger(opts \\ [])` returns all balance-counted postings
ordered by effective date and journal.

## Balance sheet

`Logistiki.balance_sheet(opts \\ [])` returns a `Logistiki.Projections.BalanceSheet`
with `assets`, `liabilities`, and `equity` sections, each with balances and a
per-currency section total. Account types map to sections:

- Assets: `asset`, `settlement`
- Liabilities: `liability`, `client`, `suspense`, `clearing`, `tax`
- Equity: `equity`

## Income statement

`Logistiki.income_statement(opts \\ [])` returns an
`Logistiki.Projections.IncomeStatement` with `income` and `expenses` sections and
a `net_profit_by_currency` map. Account types map to sections:

- Income: `income`, `fee`
- Expenses: `expense`
