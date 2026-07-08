# Business entities

Business entities represent legal, operational, customer, organizational, or
ownership structures. They are **hierarchical**, maintained through a closure
table.

```
Acme Holdings
  Acme Trading Ltd
  Acme Treasury Ltd

Bluewater Trust
  Bluewater Operating Company
```

## Schema: `business_entities`

| field | type | notes |
|-------|------|-------|
| `id` | bigint | PK |
| `parent_id` | bigint | self-reference; nil for roots |
| `name` | string | required |
| `legal_name` | string | |
| `entity_type` | string | `individual`, `company`, `trust`, `partnership`, `fund`, `bank`, `branch`, `department`, `counterparty`, `internal` |
| `status` | string | `pending`, `active`, `inactive`, `frozen`, `closed` |
| `jurisdiction` | string | |
| `external_id` | string | unique |
| `metadata` | map | |
| `inserted_at` / `updated_at` | utc_datetime | |

## Schema: `business_entity_closure`

| field | type |
|-------|------|
| `ancestor_id` | bigint |
| `descendant_id` | bigint |
| `depth` | integer |

Each row records that `ancestor` is an ancestor of `descendant` at `depth`. A
self-row has depth 0. The closure table is rewritten on insert and on
`move_entity/2` so that:

- a self-row (depth 0) is always present
- cycles are prevented
- subtree and ancestor queries are O(closure rows), not recursive CTEs

## Functions

```elixir
Logistiki.BusinessEntities.create_entity(attrs)
Logistiki.BusinessEntities.update_entity(entity, attrs)
Logistiki.BusinessEntities.get_entity!(id)
Logistiki.BusinessEntities.list_entities(opts \\ [])
Logistiki.BusinessEntities.list_children(entity)
Logistiki.BusinessEntities.list_descendants(entity)
Logistiki.BusinessEntities.list_ancestors(entity)
Logistiki.BusinessEntities.move_entity(entity, new_parent)
```

`list_descendants/1` and `list_ancestors/1` read the closure table directly,
which is fast and predictable for subtree balance aggregation and reporting.
