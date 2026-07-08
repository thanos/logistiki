# The knowledge layer

The knowledge layer is powered by [`ex_datalog`](https://hex.pm/packages/ex_datalog).
It contains business facts, accounting facts, event facts, entity facts, account
facts, relationship facts, policy facts, template facts, mapping facts, and
constraint facts.

## What the knowledge layer answers

- Should this event be processed?
- Is this event blocked?
- Does this event require approval?
- Which accounting policy applies?
- Which posting template applies?
- Which debit/credit account should be used?
- Which dimensions are required?
- Which account mapping applies?
- Which warnings should be attached?

## The important rule

**Datalog should not construct Elixir structs.** Datalog decides facts and
relationships. Elixir materializes journals, postings, and persisted records.

## Program

`Logistiki.Knowledge.Program` is an `ExDatalog.Schema` that declares:

- **Relations** for per-event runtime facts (`event_type`, `event_amount_cents`,
  `event_account`, `event_cash_account`, `event_fee_income_account`, ...).
- **Relations** for derived business rules (`blocked`, `requires_approval`).
- **Relations** for accounting policy selection (`policy`).
- **Relations** for posting templates and account roles (`template`,
  `template_posting`, `requires_dimension`, `account_role_static`,
  `account_role`).
- **Static facts** for templates, template postings, required dimensions, and
  static account mappings.
- **Rules** that derive `blocked`, `requires_approval`, `policy`, and
  `account_role` from the per-event facts.

## Runtime facts

`Logistiki.Knowledge.Facts.generate/1` builds a list of `{relation, values}`
facts from a `Logistiki.Event.Normalized` event. The event is represented by the
fixed atom `:evt` inside the Datalog program. `Logistiki.Knowledge.KnowledgeBase`
loads `Program.program/0` (which includes the compile-time static facts), adds
the runtime facts via `ExDatalog.Program.add_fact/3`, materializes the knowledge,
and interprets the result into a `Logistiki.Knowledge.Result`.

## Result

`Logistiki.Knowledge.Result` captures:

- `blocked`, `requires_approval`
- `policy` — the selected accounting policy atom
- `template` — the selected template (= the policy in v0.1.0)
- `template_postings` — ordered posting specs
- `account_roles` — `role => account_code`
- `required_dimensions`
- `explanation`

## Public API

```elixir
Logistiki.Knowledge.evaluate(normalized_event)
Logistiki.Knowledge.materialize(normalized_event)
Logistiki.Knowledge.load_program()
Logistiki.Knowledge.assert_fact(predicate, arguments)
```

`Logistiki.Knowledge.PolicySelector` and
`Logistiki.Knowledge.TemplateResolver` are thin façades for callers that only
need the policy or template decision.
