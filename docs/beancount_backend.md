# The Beancount backend

The Beancount backend (`Logistiki.Ledger.Beancount`) is the **accounting oracle**.
It uses [`beancount_ex`](https://hex.pm/packages/beancount_ex) as the executable
accounting specification. Beancount is the oracle, **not** the domain model —
Beancount-specific structs never escape the backend.

## Responsibilities

- map virtual account codes to Beancount accounts (`BeancountMapper`)
- map journals to Beancount transaction directives
- map postings to Beancount postings (signed amounts: debit `+`, credit `-`)
- validate accounting behaviour with `Beancount.check/1`
- compute balances, statements, trial balances (delegated to the projection
  engine so the Simulation and Beancount backends agree by construction)
- support regression comparison via `verify_ledger/1` and `oracle_balances/1`

## The mapper

`Logistiki.Ledger.BeancountMapper` converts at the boundary:

```elixir
BeancountMapper.to_beancount_account(account)        # %VirtualAccount{} -> "Assets:Cash:Usd:Nostro"
BeancountMapper.to_beancount_directive(journal, postings, accounts_by_code)
BeancountMapper.to_beancount_posting(posting, account)
BeancountMapper.to_beancount_opens(accounts)
BeancountMapper.from_beancount_balance(result)
BeancountMapper.from_beancount_entry(result)
```

### Account code mapping

Logistiki codes are colon-separated (`LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING`).
The mapper:

1. maps the account type to a Beancount root (`Assets`, `Liabilities`, `Equity`,
   `Income`, `Expenses`);
2. drops the Logistiki root segment and CamelCases the rest (underscores removed).

The result is deterministic, stable, human-readable, and not based only on UUIDs.
Each segment starts with an uppercase letter as Beancount requires.

### Signed amounts

Beancount encodes direction as sign: **debits are positive, credits are
negative**, regardless of account type. Account balances then read naturally
(assets positive, liabilities/income negative) and match Logistiki's
`net = debit - credit` projection.

## Backend configuration

```elixir
config :logistiki, :ledger_backend, Logistiki.Ledger.Beancount
```

At runtime: `Logistiki.put_ledger_backend(Logistiki.Ledger.Beancount)`.

The `beancount_ex` engine defaults to `Beancount.Engine.Elixir` (a pure-Elixir
booking engine) so the oracle works **without** a Python/`bean-check` install.
The real `bean-check`/`bean-query` CLI engine can be configured if desired.

## Oracle verification

`Logistiki.Ledger.Beancount.verify_ledger/1` renders all posted and reversed
journals to a Beancount ledger and runs `Beancount.check/1`.
`oracle_balances/1` runs a BQL `SELECT account, sum(position) GROUP BY account`
and returns the oracle's balances for regression comparison.

## Beancount as executable specification

Every future native backend must match Beancount behaviour for shared supported
features. The regression suite (see `docs/testing_strategy.md`) compares
Simulation-backend results against the Beancount oracle for generated valid
journals. Results must match.
