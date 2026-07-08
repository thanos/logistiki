# Journals and postings

Journals and postings are **internal accounting artifacts** created by the
runtime from business events. They may be exposed for audit, operations,
support, import/export, and admin tooling, but applications should normally
publish business events instead of creating journals directly.

## Journals

### Schema: `journals`

| field | type | notes |
|-------|------|-------|
| `id` | bigint | PK |
| `event_id` | string | the originating business event id |
| `external_id` | string | |
| `source_system` / `source_type` / `source_id` | string | provenance |
| `selected_policy` | string | recorded for explanation/replay |
| `selected_template` | string | recorded for explanation/replay |
| `description` | string | |
| `status` | string | `draft`, `validated`, `posted`, `reversed`, `rejected` |
| `effective_date` | date | |
| `posted_at` | utc_datetime | set when posted |
| `reversed_at` | utc_datetime | set when reversed |
| `reversal_of_id` | bigint | self-reference for reversals |
| `idempotency_key` | string | unique; prevents duplicate posting |
| `explanation` | map | the full knowledge-layer explanation |
| `metadata` | map | |
| `inserted_at` / `updated_at` | utc_datetime | |

### Rules

- posted journals are immutable
- rejected journals are preserved for audit
- reversals create a **new** journal that exactly negates the original postings
- the idempotency key prevents duplicate posting
- the selected policy/template are recorded for explanation and replay

## Postings

### Schema: `postings`

| field | type | notes |
|-------|------|-------|
| `id` | bigint | PK |
| `journal_id` | bigint | FK |
| `virtual_account_id` | bigint | FK; resolved from `account_code` on insert |
| `account_code` | string | denormalized for audit readability |
| `debit_credit` | string | `debit` or `credit` |
| `amount` | decimal(20,4) | always positive |
| `currency` | string | |
| `memo` | string | |
| `sequence` | integer | ordering within the journal |
| `metadata` | map | includes the symbolic `role` |
| `inserted_at` / `updated_at` | utc_datetime | |

### Rules

- amount is positive; direction encodes sign
- `debit_credit` is `debit` or `credit`
- the posting account must be a leaf, active, posting-allowed account
- the journal must balance per currency (debits = credits)
- postings are immutable once the journal is posted
- `account_code` is denormalized for audit readability but `virtual_account_id`
  remains canonical

## Reversals

A reversal is a new posted journal whose postings flip the direction of the
original postings while keeping the amount, currency, account, and sequence.
`Logistiki.Accounting.reverse_journal/2` validates that the reversal exactly
negates the original (`InvariantValidator.validate_reversal/2`), inserts the
reversal, and marks the original `reversed`. **Both** the original and the
reversal remain balance-counted (their postings net to zero).

## Administrative API

```elixir
Logistiki.Accounting.draft_journal(attrs)   # admin/test helper
Logistiki.Accounting.post_journal(journal, postings)
Logistiki.Accounting.reverse_journal(journal, attrs \\ %{})
Logistiki.Accounting.get_journal!(id)
Logistiki.Accounting.list_journals(opts \\ [])
Logistiki.Accounting.list_postings(journal)
```

These are useful for tests, migration, support tools, and controlled operations,
but they are **not** the normal application-facing API.
