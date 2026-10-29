# Baseline and Risk Register — Logistiki v0.1.1

**Baseline commit:** `b398587a78a6d4dbd815bedc7e6081be959b6713`  
**Package version inspected:** `0.1.0`  
**Inspection date:** 2026-10-28  
**Locked deps:** `beancount_ex 0.6.0`, `ex_datalog 0.5.0`, `ecto`/`ecto_sql 3.14.0`, `decimal 3.1.1`, `stream_data 1.3.0`, Elixir `~> 1.18`

## Baseline commands (pre-fix)

| Check | Result |
|---|---|
| `mix format --check-formatted` | pass |
| `mix compile --warnings-as-errors` | pass |
| `mix credo --strict` | pass (14 design suggestions, 3 readability) |
| `mix test` | **6 properties, 318 tests, 0 failures** |

## Observed process outcome taxonomy (0.1.0)

| Outcome | Return shape | Durable evidence |
|---|---|---|
| **posted** | `{:ok, %Result{journal: %Journal{status: "posted"}}}` | journal+postings in txn; event status update *after*; audit *after* |
| **no-accounting-impact** | `{:ok, %Result{journal: nil, explanation: %{reason: :no_accounting_impact}}}` | event may stay `normalized`; audit after |
| **blocked** | `{:error, %Error{code: :blocked_event}}` | event left `normalized`; **no** decision audit |
| **approval-required** | `{:error, %Error{code: :approval_required}}` | same as blocked |
| **already-processed** | **not implemented** | duplicate → `:duplicate_idempotency_key` or `:backend_error` |
| **recoverable failure** | crash / MatchError / `:backend_error` | partial writes possible |
| **terminal failure** | `{:error, %Error{}}` (policy/invariant) | may leave orphan `normalized` event |

## Confirmed defects (static + architectural; not all reproduced as exploits)

1. **Nonfatal event persistence** — `persist_stage/2` continues on insert failure; journals can post with no durable business event (`pipeline.ex`).
2. **Audit after ledger commit** — mandatory provenance is not in the journal transaction; audit insert errors are ignored; hard `{:ok, _} = audit_stage(...)` can MatchError after money moved.
3. **No end-to-end transaction** — event, journal/postings, audit, and status are separate commits.
4. **No unique `(source_system, source_id)`** on `business_events`; no `external_event_id` / payload fingerprint.
5. **Idempotency TOCTOU** — `Repo.exists?` then insert; race losers mistyped as `:backend_error`.
6. **No already-processed replay** — retries do not return the original Result.
7. **No payload-conflict detection** — same key / different amount not distinguished.
8. **Reversal race** — no `FOR UPDATE` / CAS on `status=posted`; no unique on `reversal_of_id`.
9. **Immutability is Elixir-only** — no DB triggers on posted journals/postings.
10. **Account freeze TOCTOU** — status checked outside posting lock.
11. **No account.currency vs posting.currency check.**
12. **No currency precision rejection** beyond Decimal scale 4 storage.
13. **No `as_of` projection filter.**
14. **No outcome lookup API** after timeout/crash.
15. **Simulation and Beancount share ProjectionEngine** for balance/statement/trial_balance — oracle independence is verify_ledger only.
16. **Nil event id** → random idempotency key → retries non-idempotent.

## L11 scenario status on baseline (before fix)

| ID | Expected to pass on 0.1.0? |
|---|---|
| L11-01 Ordinary USD deposit | Partial (happy path exists; not in v011 suite) |
| L11-02 Event persist forced failure | **Fail** (nonfatal persist) |
| L11-03 Journal/posting DB failure | Partial txn for journal only |
| L11-04 Mandatory audit failure | **Fail** |
| L11-05 Concurrent identical requests | **Fail** (no typed replay) |
| L11-06 Same key, different amount | **Fail** |
| L11-07 Crash before commit | Untested |
| L11-08 Crash after commit + lookup | **Fail** (no lookup API) |
| L11-09 Concurrent reversals | **Fail** |
| L11-10 Reverse already reversed | Partial (serial only) |
| L11-11 Mutate posted rows | **Fail** (no DB protection) |
| L11-12 Unbalanced / non-postable | Partial |
| L11-13 Multi-currency imbalance | Partial |
| L11-14 Decimal / precision | Partial |
| L11-15 Frozen account race | **Fail** |
| L11-16 Two legal entities | Partial |
| L11-17 As-of statement + reversal | **Fail** / weak |
| L11-18 Beancount differentials | Partial |
| L11-19 No-impact and blocked | Partial (no durable decision evidence) |
| L11-20 Failed policy evaluation | Partial |
| L11-21 DB reconnect / OTP restart | **Fail** / untested |
| L11-22 Embedding smoke | **Fail** / untested |

## Outstanding risks after v0.1.1 (to be refined in KNOWN_LIMITATIONS)

- Atomicity is **Logistiki.Repo only** — not distributed with Jewelbank.Repo or external banks.
- Same-DB shared-Repo with host apps is **out of scope**.
- No claim of banking-production certification.
- Property/concurrency coverage is necessary but not exhaustive of all isolation anomalies.
