defmodule Logistiki.Knowledge.Rules do
  @moduledoc """
  Documentation and helpers for the three rule categories in Logistiki.

  ## Business rules (Datalog-backed)

  Answer: should this event be processed? Is it blocked? Is approval needed?
  Is compliance review needed? Is it operationally allowed?

  Implemented as Datalog rules in `Logistiki.Knowledge.Program` (`blocked`,
  `requires_approval`).

  ## Accounting policies (Datalog-backed)

  Answer: which accounting policy applies? Which posting template applies?
  Which account roles are used? Which dimensions are required? Which valuation
  method applies?

  Implemented as Datalog rules (`policy`) and facts (`template`,
  `template_posting`, `requires_dimension`, `account_role_static`).

  ## Ledger invariants (pure Elixir)

  Answer: what must *always* be true? Implemented in
  `Logistiki.Accounting.InvariantValidator`. These must never depend on Datalog.

  Datalog may say what should happen. Elixir enforces what must always be true.
  """

  @categories [
    business_rules: "Datalog-backed: should the event be processed / blocked / approved?",
    accounting_policies: "Datalog-backed: which policy, template, roles, dimensions apply?",
    ledger_invariants: "Pure Elixir: debits equal credits, postings positive, immutable, etc."
  ]

  @doc "Returns the rule categories with descriptions."
  def categories, do: @categories
end
