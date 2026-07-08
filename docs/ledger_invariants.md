# Ledger invariants

Ledger invariants are **hard accounting rules enforced in pure Elixir**. They
must **never** depend on Datalog. Datalog may say what should happen; Elixir
enforces what must always be true.

## `Logistiki.Accounting.InvariantValidator`

### Invariants

- a journal has at least two postings
- postings reference existing accounts
- postings target leaf, active, posting-allowed accounts
- amounts are positive
- currencies are present
- `debit_credit` is `debit` or `credit`
- debits equal credits **per currency**
- the idempotency key is unique among posted journals
- frozen/closed accounts reject postings
- a reversal exactly negates the original postings
- posted journals are immutable (enforced at the context layer)

### Functions

```elixir
InvariantValidator.validate(journal, postings)        # full check
InvariantValidator.validate_postings(postings)         # non-DB invariants
InvariantValidator.validate_accounts(postings)         # leaf/postable checks
InvariantValidator.validate_idempotency(key)           # uniqueness among posted
InvariantValidator.validate_reversal(original, reversal)
```

### Errors

Invariant failures return `{:error, %Logistiki.Error{}}` with `code` and
`stage: :invariant_validation`:

- `:unbalanced_journal` (too few postings, unbalanced, negative amount, missing
  currency, bad direction)
- `:account_not_found`
- `:account_not_postable`
- `:duplicate_idempotency_key`

## Why these are not in Datalog

Datalog derives what *should* be true from the current knowledge program.
Invariants are what must *always* be true, regardless of the program. Keeping
them in deterministic Elixir means a bad rule can never produce an unbalanced
journal, a posting to a parent account, or a mutated posted journal.
