# Testing strategy

Logistiki uses TDD with ExUnit and StreamData. Tests run against PostgreSQL
through `Ecto.Adapters.SQL.Sandbox` (see `test/support/data_case.ex`).

## Layout

- `test/logistiki/business_entities/` — entity hierarchy and closure table
- `test/logistiki/virtual_accounts/` — account hierarchy and closure table
- `test/logistiki/relationships/` — entity-account links
- `test/logistiki/events/` — normalization and persistence
- `test/logistiki/knowledge/` — fact generation, policy selection, templates
- `test/logistiki/accounting/invariant_validator_test.exs` — hard invariants
- `test/logistiki/ledger/` — simulation and Beancount backends, agreement
- `test/logistiki/projections/` — balance, statement, trial balance, sheets
- `test/logistiki/integration_test.exs` — full pipeline end-to-end
- `test/logistiki/property_test.exs` — StreamData property tests

## Coverage by category

### Business entity tests
create root/child, query descendants/ancestors, move, prevent cycles, preserve
closure correctness.

### Virtual account tests
create root/child, query descendants/ancestors, prevent cycles, prevent posting
to parent, require currency for posting accounts, allow nil currency for
aggregation accounts, closure correctness.

### Relationship tests
link entity→account, many entities per account, many accounts per entity,
query accounts for entity / entity subtree, respect `valid_from`/`valid_to`.

### Business event tests
normalize known events, reject invalid events, no-accounting-impact events,
preserve source fields, persist.

### Knowledge layer tests
generate facts, evaluate business rules, block by rule, mark approval required,
select policy, detect no-policy, resolve template, resolve account roles,
static fallback.

### Journal/posting tests
build journal from selected template, reject unbalanced journals, reject posting
to parent, reject negative amount, post valid journal, prevent duplicate
idempotency key, reverse posted journal, reject reversal of draft.

### Projection tests
balance leaf/parent, balance entity-owned, balance entity subtree, statement
with running balance, trial balance, trial balance balances per currency,
balance sheet, income statement, general ledger.

### Backend tests
simulation executes valid journal, Beancount maps deterministic valid accounts,
Beancount executes valid journal, Beancount-specific types do not leak into the
public API, simulation and Beancount agree.

## Property tests (StreamData)

- balanced journals always accepted
- unbalanced journals always rejected
- reversal restores affected balances to zero
- parent account balance equals the sum of descendant balances
- posting order does not change the final balance
- simulation and Beancount backends agree for generated valid journals

## Beancount as executable specification

The regression suite compares:

```
Generated Business Event
    → Logistiki + Beancount Backend → balances / trial balance / statements

Generated Business Event
    → Logistiki + Simulation Backend → balances / trial balance / statements
```

Results must match.

## Running

```bash
mix test                    # full suite (uses logistiki_test DB)
mix test --only property    # property tests
mix credo                   # static analysis
```
