# Known Limitations — Logistiki v0.1.1

This release hardens the embedded accounting engine for reliable banking **library**
use. It is **not** a declaration of banking-production certification.

## Atomicity

- Atomicity is limited to **`Logistiki.Repo`** (one PostgreSQL database).
- There is **no** distributed transaction with Jewelbank.Repo, Mnesia/Kathikon,
  payment rails, or external banks. Hosts must use the documented recovery
  protocol (`lookup_outcome/1` + stable identities).

## Availability vs booked balance

- `balance`, `statement`, and `trial_balance` are **booked/posting projections**
  over immutable postings.
- They are **not** funds-available balances. Holds, pending settlement, and
  overdraft rules belong to the host product layer (e.g. Jewel Core).

## Oracle independence

- Simulation and Beancount backends share `ProjectionEngine` for public
  projection APIs by design.
- Beancount's oracle value is exercised by pre-commit verification and
  `verify_ledger/1` / L11-18 fixtures — not by comparing ProjectionEngine to
  itself across backends.

## Schema / embedding

- Jewel **separate database** is the supported reference model.
- Same-DB shared-Repo with host apps is **out of scope** for 0.1.1 (table name
  collisions such as `business_events`).

## Concurrency & isolation

- Lock/uniqueness tests assume **PostgreSQL** (default adapter).
- Supported semantics use standard Postgres isolation with `FOR UPDATE` on
  accounts/journals and unique constraints; not every theoretical anomaly is
  exhaustively proven.

## Precision & FX

- Currency precision uses an explicit map (USD/EUR 2, JPY 0, default max scale 4).
- Cross-currency journals must balance **per currency**; no implicit FX clearing
  or valuation engine is provided.

## Async audit enrichment

- Mandatory provenance is synchronous inside Commit.
- Stage-level enrichment is durable in `audit_pending` and drained asynchronously
  (synchronously in tests). Drain failure does not roll back money movement.

## Outstanding risks

- Host mis-retry with a **new** idempotency key still creates a second event
  (contract violation by the caller).
- Property and concurrency suites reduce but do not eliminate residual race risk
  under extreme load or non-Postgres adapters.
- No claim of SOC2 / banking regulator certification.
