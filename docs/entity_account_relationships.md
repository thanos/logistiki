# Entity-account relationships

Business entities and virtual accounts are separate hierarchies. They connect
through relationships that support many-to-many links, multiple relationship
types between the same pair, and effective dating.

## Schema: `entity_accounts`

| field | type | notes |
|-------|------|-------|
| `id` | bigint | PK |
| `business_entity_id` | bigint | FK |
| `virtual_account_id` | bigint | FK |
| `relationship_type` | string | `owner`, `beneficiary`, `controller`, `signatory`, `viewer`, `trustee`, `related_party`, `manager`, `custodian` |
| `valid_from` | date | required |
| `valid_to` | date | nil while active |
| `metadata` | map | |
| `inserted_at` / `updated_at` | utc_datetime | |

A unique index allows multiple relationship types between the same entity and
account, but prevents duplicates of the same `(entity, account, type)` triple.

## Functions

```elixir
Logistiki.Relationships.link_entity_account(entity, account, relationship_type, attrs \\ %{})
Logistiki.Relationships.unlink_entity_account(entity, account, relationship_type)
Logistiki.Relationships.list_accounts_for_entity(entity, opts \\ [])
Logistiki.Relationships.list_accounts_for_entity_tree(entity, opts \\ [])
Logistiki.Relationships.list_entities_for_account(account, opts \\ [])
```

## Effective dating

`list_*` functions accept an `:at` option (a `Date`) to filter relationships
active at a point in time, and a `:relationship_type` option to filter by type.

## Why this matters for balances

Relationships are how entity balances are computed:

- `balance_for_entity/2` aggregates accounts linked to an entity
- `balance_for_entity_tree/2` aggregates accounts linked to an entity **or any of
  its descendants** (using the business-entity closure table)

This lets you ask "what is the total client liability for the Acme Holdings
subtree?" without duplicating account trees for reporting dimensions.
