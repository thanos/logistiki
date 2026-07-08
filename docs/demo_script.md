# Demo script

The demo scenario (`Logistiki.Demo.run_demo/0`) seeds the demo entity and account
trees, links entities to accounts, and processes the demo business events
end-to-end through the accounting pipeline.

## Running

On a fresh, migrated database:

```bash
mix ecto.drop && mix ecto.create && mix ecto.migrate
mix run -e 'Logistiki.Demo.run_demo()'
```

Or use the simulation backend explicitly and switch to the Beancount oracle:

```elixir
Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation)
Logistiki.Demo.run_demo()

Logistiki.put_ledger_backend(Logistiki.Ledger.Beancount)
Logistiki.Demo.run_demo()
```

## Demo business entities

```
Acme Holdings
  Acme Trading Ltd
  Acme Treasury Ltd

Bluewater Trust
  Bluewater Operating Company
```

## Demo virtual accounts

```
Assets
  Cash
    USD
      Nostro USD

Liabilities
  Client Deposits
    USD
      Acme Holdings
        Operating
        Payroll
        Escrow
      Bluewater Trust
        Operating

Income
  Fees
    Wire Fees

Expenses
  Interest Expense

Suspense
  USD Suspense
```

## Demo events

1. Deposit received for Acme Operating.
2. Internal transfer from Acme Operating to Acme Payroll (template available).
3. Wire fee assessed to Acme Operating.
4. Mistaken fee reversed.
5. Suspense posting corrected (template available).
6. Customer account opened with no accounting impact.

## What the demo shows

1. Load knowledge program.
2. Create entity tree.
3. Create account tree.
4. Link entities to accounts.
5. Process deposit event.
6. Show policy selected by Datalog (`:cash_deposit`).
7. Show generated journal.
8. Show generated postings.
9. Show ledger backend execution.
10. Show balance.
11. Show statement (with running balance).
12. Process fee event (`:corporate_wire_fee`).
13. Reverse the fee.
14. Show balance restored.
15. Show audit evidence explaining everything.

## Seed script

`priv/repo/seeds.exs` seeds the demo entity and account trees (idempotent — it
skips if entities already exist). Run with `mix ecto.setup` or
`mix ecto.reset`.
