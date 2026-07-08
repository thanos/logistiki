# Vision

Logistiki is an embedded OTP accounting engine for Elixir applications.

Applications embed Logistiki to obtain business event processing, a Datalog-backed
accounting knowledge layer, double-entry accounting, immutable journals and
postings, hierarchical business entities and virtual accounts, entity-to-account
relationship graphs, derived balances and statements, audit evidence,
deterministic replay, behaviour-based ledger backends, and a Beancount-backed
accounting oracle.

## Design supports

Banks, FinTech platforms, ERPs, treasury platforms, crypto exchanges, brokerages,
insurance platforms, asset managers, family offices, marketplaces, internal
accounting systems, and regulated transaction systems — **without baking any one
of those domains into the accounting engine**.

## Core philosophy

Money never moves because random application code says so. Money moves because a
business event happened, the knowledge layer evaluated the rules, a policy was
selected, a template was resolved, a journal was built, invariants were
validated, and a ledger backend executed it.

Everything must be:

- **explainable** — every posting traces back to a business event, a policy, a
  template, and the rules that fired
- **reproducible** — the same event under the same knowledge program produces the
  same journals and postings
- **immutable once posted** — posted journals and their postings never change
- **auditable** — every important action records audit evidence
- **testable** — pure functions, deterministic invariants, property tests
- **replayable** — event payload, selected policy, template, and program version
  are persisted
- **backend-independent** — `Logistiki.Ledger.Behaviour` abstracts the backend

## Layering

The application owns business processes. Logistiki owns accounting execution.
The two communicate through business events and queries — never through direct
journal creation.

1. **Business events** — application-facing input
2. **Knowledge layer** — `ex_datalog` facts, rules, policies, templates, mappings
3. **Accounting runtime** — deterministic Elixir that builds, validates, persists
4. **Ledger backend** — `Logistiki.Ledger.Behaviour` (Simulation or Beancount)

## Non-goals for v0.1.0

Payment rails, SWIFT/ISO 20022/ACH, card processing, KYC/AML/sanctions/PEP,
onboarding workflows, a workflow engine, regulatory reporting, PDF statements,
invoicing, tax filing, ERP modules, a blockchain ledger, distributed consensus,
a Phoenix dashboard, and a standalone accountant app. Those are applications or
later integrations. Logistiki v0.1.0 is the embedded accounting engine.

## Roadmap

- **v0.1.0** — business event API, Datalog knowledge layer, policy/template
  selection, hierarchical entities/accounts, entity-account relationships,
  journals/postings as internal artifacts, invariant validation, simulation and
  Beancount backends, balance/statement/trial-balance projections, audit
  evidence, property tests.
- **v0.2.0** — richer policy versioning, a replay engine, comparison between
  policy versions, knowledge-program import/export, richer reporting.
- **v0.3.0** — a native Elixir ledger backend with a full regression suite
  against the Beancount oracle, performance work, streaming projections.
- **v0.4.0** — a Phoenix LiveView dashboard package.
- **v0.5.0** — a standalone accountant application foundation.
- **Future** — a Rust backend, a distributed ledger backend, Arrow export, an
  audit-evidence lake, integrations with Kathikon, ExArrow, ExDataSketches, Mneme.
