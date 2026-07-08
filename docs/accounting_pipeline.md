# The accounting pipeline

The accounting pipeline is the defining mental model of Logistiki. Each stage is
represented in code (`Logistiki.Accounting.Pipeline`), recorded in the audit
trail, and emitted as telemetry.

```
Business Event
    │
    ▼
Event Normalization
    │
    ▼
Datalog Fact Generation
    │
    ▼
Business Rule Evaluation
    │
    ▼
Accounting Policy Selection
    │
    ▼
Accounting Template Resolution
    │
    ▼
Journal Builder
    │
    ▼
Posting Builder
    │
    ▼
Ledger Invariant Validation
    │
    ▼
Ledger Backend Execution
    │
    ▼
Projection Generation
    │
    ▼
Audit Evidence
```

## Stages

### 1. Event normalization

`Logistiki.Event.normalize/1` dispatches to the event struct's `Logistiki.Event`
implementation and returns a `Logistiki.Event.Normalized` struct — the canonical,
flattened representation the knowledge layer consumes.

### 2. Datalog fact generation

`Logistiki.Knowledge.Facts.generate/1` turns the normalized event into a list of
`{relation, values}` facts (e.g. `{:event_type, [:evt, :deposit_received]}`,
`{:event_amount_cents, [:evt, 100000]}`). The event is represented inside the
Datalog program by the fixed atom `:evt`.

### 3. Business rule evaluation

The knowledge program (`Logistiki.Knowledge.Program`) derives `blocked(:evt)` and
`requires_approval(:evt)`. A blocked event short-circuits with
`%Logistiki.Error{code: :blocked_event}`; an event requiring approval
short-circuits with `%Logistiki.Error{code: :approval_required}`. Events with no
accounting impact produce a valid result with `journal: nil`.

### 4. Accounting policy selection

The program derives `policy(:evt, policy_name)` from the event's facts. Exactly
one policy must match; zero matches yields `:no_policy_found`, and ambiguity is
resolved deterministically (sorted, first wins) with a warning.

### 5. Template resolution

For the selected policy, the program's `template_posting/6` facts describe the
posting specs (sequence, direction, role, amount/currency variables). The
`account_role/3` rules resolve each symbolic role (`:cash_account`,
`:client_liability_account`, `:fee_income_account`, ...) to a concrete account
code — either from event-provided facts or a static `account_role_static/2`
fallback.

### 6–7. Journal & posting builder

`Logistiki.Accounting.JournalBuilder` and `Logistiki.Accounting.PostingBuilder`
materialize the knowledge result into a draft `%Journal{}` with draft
`%Posting{}` structs. **Datalog never constructs structs**; Elixir does.

### 8. Ledger invariant validation

`Logistiki.Accounting.InvariantValidator` enforces the hard accounting
invariants in **pure Elixir** (debits = credits per currency, positive amounts,
leaf posting accounts, idempotency uniqueness, exact reversal). These checks
**never depend on Datalog**.

### 9. Ledger backend execution

The configured backend (`Logistiki.Ledger.Simulation` or
`Logistiki.Ledger.Beancount`) executes the journal — persisting it as `posted`
and (for the Beancount backend) verifying it with `Beancount.check/1`.

### 10. Projection generation

Balances, statements, trial balances, and other projections are computed from
the now-immutable postings by `Logistiki.Projections.ProjectionEngine`.

### 11. Audit evidence

Every stage is recorded as an `audit_events` row by `Logistiki.Audit`, so the
full chain — event → rules → policy → template → journal → postings → ledger
result — can be explained later.

## Telemetry

Each stage emits `:telemetry` events (see `Logistiki.Telemetry.events/0`), e.g.
`[:logistiki, :knowledge, :evaluate, :stop]`, `[:logistiki, :journal, :build, :stop]`,
`[:logistiki, :ledger, :execute, :stop]`, `[:logistiki, :audit, :write, :stop]`.
