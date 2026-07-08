# Audit evidence

Every important action in the accounting pipeline records audit evidence so
that, later, one can answer:

- Why did this posting exist?
- Which business event caused it?
- Which rules fired?
- Which policy was selected?
- Which template was used?
- Which accounts were selected?
- Who initiated it?
- When did it post?
- How was the balance derived?

## Schema: `audit_events`

| field | type | notes |
|-------|------|-------|
| `id` | bigint | PK |
| `actor_id` | string | |
| `event_id` | string | the originating business event |
| `journal_id` | bigint | FK |
| `action` | string | the stage action (see below) |
| `resource_type` | string | |
| `resource_id` | string | |
| `before` | map | |
| `after` | map | |
| `explanation` | map | the stage's explanation |
| `metadata` | map | |
| `inserted_at` | utc_datetime | |

## Captured actions

- `business_event_received`
- `event_normalized`
- `facts_generated`
- `business_rules_evaluated`
- `no_accounting_impact`
- `policy_selected`
- `template_selected`
- `journal_built`
- `invariant_validation_succeeded`
- `invariant_validation_failed`
- `journal_posted`
- `journal_reversed`
- `projection_generated`
- `audit_event_written`

## API

```elixir
Logistiki.Audit.record(attrs)
Logistiki.Audit.record_evidence(%Logistiki.Audit.Evidence{})
Logistiki.Audit.list_audit_events(opts \\ [])
Logistiki.Audit.trail_for_event(event_id)
Logistiki.Audit.trail_for_journal(journal_id)
```

The pipeline calls `record_evidence/1` once per event with an
`Logistiki.Audit.Evidence` struct that bundles every stage's action and
explanation, then records an `audit_event_written` marker.

## Explanation

`Logistiki.Accounting.Result.explanation` and each journal's `explanation` map
preserve the full knowledge-layer decision (`policy`, `template`,
`account_roles`, `knowledge_explanation`), the originating event id and type,
and the ledger result status. Combined with the audit trail, this makes every
posting fully explainable.
