# Business events

Business events are the application-facing input to Logistiki. They represent
business intent and carry enough data for the knowledge layer to decide whether
the event is allowed, whether approvals are required, whether it creates
accounting impact, which policy applies, which template applies, which accounts
are involved, which dimensions are required, and how audit evidence should be
recorded.

## Defining an event

Use the `Logistiki.Event` behaviour macro:

```elixir
defmodule Logistiki.Event.DepositReceived do
  use Logistiki.Event, type: "deposit_received"

  defevent do
    field :cash_account_code, :string
  end
end
```

`use Logistiki.Event, type: "..."` declares the event type and generates an
`event_type/1` and `normalize/1` implementation. `defevent` declares the event's
embedded schema — the common normalized fields (`id`, `amount`, `currency`,
`account_code`, `entity_type`, ...) plus any event-specific fields. Extra
event-specific fields are merged into the `Logistiki.Event.Normalized` struct
during normalization.

## Built-in events

| Module | Type | Accounting impact |
|--------|------|-------------------|
| `Logistiki.Event.DepositReceived` | `deposit_received` | debit cash, credit client liability |
| `Logistiki.Event.TransferSettled` | `transfer_settled` | debit destination, credit source |
| `Logistiki.Event.FeeAssessed` | `fee_assessed` | debit client liability, credit fee income |
| `Logistiki.Event.InterestAccrued` | `interest_accrued` | debit interest expense, credit client liability |
| `Logistiki.Event.RefundIssued` | `refund_issued` | debit client liability, credit cash |
| `Logistiki.Event.InvoicePaid` | `invoice_paid` | debit counterparty, credit client |
| `Logistiki.Event.AccountOpened` | `account_opened` | **none** (audit only) |

## Events with no accounting impact

Some events produce no journal (e.g. a customer opened an account, a document was
uploaded, an approval was granted). Declare `has_accounting_impact: false`:

```elixir
defevent do
  field :has_accounting_impact, :boolean, default: false
end
```

A result with no journal is valid:

```elixir
{:ok, %Logistiki.Accounting.Result{journal: nil, explanation: %{reason: :no_accounting_impact}}}
```

## The normalized event

`Logistiki.Event.Normalized` is the canonical, flattened representation used by
the knowledge layer. Fields include `id`, `type`, `source_system`, `source_id`,
`actor_id`, `occurred_at`, `effective_date`, `amount`, `currency`, `entity_id`,
`account_id`, `account_code`, `cash_account_code`, `fee_income_account_code`,
`interest_expense_account_code`, `destination_account_code`, `counterparty_id`,
`product_code`, `jurisdiction`, `fee_type`, `entity_type`,
`has_accounting_impact`, and `metadata`. Not every event populates every field.

## Persistence

`Logistiki.Events.persist/1` stores the raw event payload alongside its
normalized form in `business_events`, enabling replay and audit. The pipeline
persists events automatically; the persisted status moves `received → normalized
→ processed` (or `no_accounting_impact` / `blocked` / `requires_approval` /
`failed`).
