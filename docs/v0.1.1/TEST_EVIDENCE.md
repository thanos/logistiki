# Test Evidence — Logistiki v0.1.1

## Commands

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo
mix test --include concurrency --include postgres
```

Captured local run (2026-10-28):

```text
Finished in 8.4 seconds (0.7s async, 7.7s sync)
8 properties, 340 tests, 0 failures
```

Full console output: [`test_run.log`](test_run.log).

## L11 suite

Location: `test/logistiki/v011/`

| ID | Covered in |
|---|---|
| L11-01…L11-12 | `durability_test.exs` |
| L11-13…L11-20 | `accounting_correctness_test.exs` |
| L11-21…L11-22 + properties | `ops_and_properties_test.exs` |

Concurrency cases are tagged `@tag :concurrency` and `@tag :postgres`. CI runs
`mix test --include concurrency --include postgres` so they cannot be silently
skipped by default filters.

## Baseline vs release

| Metric | 0.1.0 baseline | 0.1.1 |
|---|---|---|
| Tests | 318 + 6 properties | 340 + 8 properties |
| Failures | 0 | 0 |
| Format / compile --warnings-as-errors | pass | pass |

## Failure injection

Test-only `Application.put_env(:logistiki, :inject_commit_failure, :event | :journal | :audit)`
exercises L11-02…L11-04 without external fault injectors. Production code paths
ignore the env unless explicitly set.
