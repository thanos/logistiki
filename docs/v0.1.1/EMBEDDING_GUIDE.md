# Embedding Guide — Logistiki v0.1.1

## Reference integration: separate database (Jewel-compatible)

Logistiki v0.1.1 is designed to run with its **own PostgreSQL database** and
`Logistiki.Repo`, independent of the host application's Repo (e.g.
`Jewelbank.Repo`). Table names such as `business_events` may overlap with host
schemas — **do not** point both Repos at the same database without a future
collision/migration plan (explicitly out of scope for 0.1.1).

## 1. Dependency

```elixir
# mix.exs
{:logistiki, "~> 0.1.1"}
```

## 2. Configure `Logistiki.Repo`

```elixir
# config/runtime.exs (or config/config.exs)
config :logistiki, Logistiki.Repo,
  url: System.fetch_env!("LOGISTIKI_DATABASE_URL"),
  pool_size: String.to_integer(System.get_env("LOGISTIKI_POOL_SIZE", "10"))

config :logistiki, :ledger_backend, Logistiki.Ledger.Simulation
# optional: Logistiki.Ledger.Beancount
```

## 3. Start OTP supervision

Ensure the `:logistiki` application starts (Mix does this when it is a
dependency), or supervise `Logistiki.Repo` yourself:

```elixir
children = [
  Logistiki.Repo
  # ... host children
]
```

`Logistiki.Application` already starts `Logistiki.Repo` under a `:one_for_one`
supervisor when the `:logistiki` app boots.

## 4. Run migrations

```elixir
path = Application.app_dir(:logistiki, "priv/repo/migrations")
Ecto.Migrator.run(Logistiki.Repo, path, :up, all: true)
```

Or from Mix in the library project: `mix ecto.create && mix ecto.migrate`.

## 5. Process events and reconcile

```elixir
case Logistiki.process(event) do
  {:ok, result} ->
    # persist host-side correlation with result.journal.id / result.event_id

  {:error, %Logistiki.Error{code: :idempotency_conflict}} ->
    # same identity, different payload — do not retry with a new key

  {:error, error} ->
    # typed failure
end

# After timeout / unknown outcome:
Logistiki.lookup_outcome(event_id: event.id)
```

## 6. Close connections

Stop the `:logistiki` application or terminate `Logistiki.Repo` on host shutdown.
No private startup hooks beyond Repo + migrations are required.

## Public API compatibility (0.1.0 → 0.1.1)

| API | Compatibility |
|---|---|
| `Logistiki.process/1,2` | Same return shape `{:ok, Result} \| {:error, Error}`; stronger durability |
| `Logistiki.balance/2`, `statement/2`, `trial_balance/1` | Compatible; add optional `:as_of` |
| `Logistiki.Ledger.reverse_journal/3` | Compatible; at-most-once under concurrency |
| `Logistiki.lookup_outcome/1` | **New** in 0.1.1 |
| `Logistiki.Ledger.Behaviour` | Preserved |
| `%Logistiki.Error{}` | Preserved; new codes additive |

## Same-DB shared Repo

Not supported in v0.1.1. Treat as a future design requiring an explicit
migration and table-collision plan.
