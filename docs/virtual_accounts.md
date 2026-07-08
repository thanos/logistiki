# Virtual accounts

Virtual accounts represent accounting accounts and account-like projections. They
are **hierarchical** and maintained through a closure table.

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

Income
  Fees
    Wire Fees

Expenses
  Interest Expense

Suspense
  USD Suspense
```

## Important principle

**Virtual accounts are not balances.** Balances are derived from postings.

## Schema: `virtual_accounts`

| field | type | notes |
|-------|------|-------|
| `id` | bigint | PK |
| `parent_id` | bigint | self-reference; nil for roots |
| `code` | string | unique, stable, human-readable (colon-separated) |
| `name` | string | required |
| `account_type` | string | `asset`, `liability`, `equity`, `income`, `expense`, `client`, `settlement`, `suspense`, `fee`, `tax`, `clearing` |
| `currency` | string | required for posting accounts; nil allowed for aggregation accounts |
| `status` | string | `active`, `inactive`, `frozen`, `closed` |
| `posting_allowed` | boolean | only leaf accounts may allow postings |
| `normal_balance` | string | `debit` or `credit` |
| `external_id` | string | |
| `metadata` | map | |
| `inserted_at` / `updated_at` | utc_datetime | |

## Schema: `virtual_account_closure`

| field | type |
|-------|------|
| `ancestor_id` | bigint |
| `descendant_id` | bigint |
| `depth` | integer |

Self-rows (depth 0) are always present; the closure is rewritten on insert and on
`move_account/2`. Cycles are prevented.

## Rules enforced

- account code is unique
- only leaf accounts (no children) may allow postings
- posting accounts require a currency
- aggregation accounts may have a nil currency
- a child cannot be created under a posting account
- cycles are forbidden on move

## Functions

```elixir
Logistiki.VirtualAccounts.create_account(attrs)
Logistiki.VirtualAccounts.update_account(account, attrs)
Logistiki.VirtualAccounts.get_account!(id)
Logistiki.VirtualAccounts.get_account_by_code!(code)
Logistiki.VirtualAccounts.list_accounts(opts \\ [])
Logistiki.VirtualAccounts.list_children(account)
Logistiki.VirtualAccounts.list_descendants(account)
Logistiki.VirtualAccounts.list_ancestors(account)
Logistiki.VirtualAccounts.move_account(account, new_parent)
Logistiki.VirtualAccounts.leaf?(account)
Logistiki.VirtualAccounts.posting_account?(account)
```

## Account types → financial-statement sections

`Logistiki.Projections.ProjectionEngine` maps account types to balance-sheet and
income-statement sections:

- **Assets**: `asset`, `settlement`
- **Liabilities**: `liability`, `client`, `suspense`, `clearing`, `tax`
- **Equity**: `equity`
- **Income**: `income`, `fee`
- **Expenses**: `expense`
