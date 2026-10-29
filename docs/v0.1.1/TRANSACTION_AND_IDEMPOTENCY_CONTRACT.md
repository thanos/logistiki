# Transaction and Idempotency Contract — Logistiki v0.1.1

## Atomicity scope

One **`Logistiki.Repo` database transaction** (via `Ecto.Multi` in
`Logistiki.Accounting.Commit`) durably binds, for an accepted financial post:

1. Business event row (`processed`) with `external_event_id` and `payload_fingerprint`
2. Exactly one journal (`posted`) and all postings
3. Mandatory provenance audit row (`action: commit_provenance`)
4. Optional enriched stages enqueued to `audit_pending`

If any Multi step fails, **nothing** from that Multi is committed. Callers never
observe `{:ok, posted}` before the commit is durable.

**Not covered:** Jewelbank.Repo, Kathikon/Mnesia, external banks, or any
cross-database distributed transaction.

## Pure vs write stages

Normalization, Datalog/knowledge, policy/template selection, and invariant
validation run **outside** the Multi. Only durable writes enter Commit.

Beancount oracle verification (when that backend is selected) runs **before**
Commit so oracle rejection produces zero durable financial effect.

## Idempotency identities

| Identity | Enforcement |
|---|---|
| Business `event.id` → `business_events.external_event_id` | Unique (partial, NOT NULL) |
| `source_system` + `source_id` | Unique when both present |
| Journal `idempotency_key` (`evt:#{id}:policy:#{policy}`) | Unique |
| Reversal | Unique `journals.reversal_of_id` + CAS `posted→reversed` |

Accounting-impact events **require** a non-nil `event.id`.

### Same key, same payload fingerprint

Return `{:ok, %Result{explanation: %{outcome: :already_processed, ...}}}` with
the original journal/postings. No second financial effect.

### Same key, different fingerprint

Return `{:error, %Error{code: :idempotency_conflict}}`. No second financial effect.

## Non-posting decisions

`:no_accounting_impact`, `:blocked`, and `:approval_required` persist a business
event (correct status) + decision provenance **without** journals/postings.

## Outcome lookup after timeout

```elixir
Logistiki.lookup_outcome(event_id: "evt_001")
Logistiki.lookup_outcome(source_system: "bank_core", source_id: "wire_123")
```

Hosts must reconcile unknown results with lookup using the **same** identity —
never invent a new idempotency key on retry.

## Jewel recovery protocol (separate databases)

1. Publish business event to Jewelbank (host DB) with a stable identity.
2. Call `Logistiki.process/1` with the same identity.
3. On timeout/crash: `Logistiki.lookup_outcome/1`.
4. If `:not_found`, safe to retry `process/1` with the **same** event.
5. If `{:ok, result}`, record the Logistiki outcome in the host DB; do not re-key.

## Immutability

PostgreSQL triggers reject UPDATE/DELETE on `postings` and reject journal
mutations except the documented `posted → reversed` (+ `reversed_at`) transition.
Corrections are compensating journals only.
