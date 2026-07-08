defmodule Logistiki.Knowledge.Program do
  @moduledoc """
  The Datalog knowledge base for Logistiki.

  This module is an `ExDatalog.Schema` that declares the relations, the
  accounting policies, posting templates, account-role resolution rules, and
  business rules that govern how business events become accounting entries.

  ## Static knowledge (compile-time facts)

  Templates, template postings, required dimensions, and static account
  mappings are declared as facts and are stable across events.

  ## Runtime knowledge (per event)

  Per-event facts (`event_type`, `event_amount_cents`, `event_account`, ...) are
  added at runtime by `Logistiki.Knowledge.Facts` before materialization.

  ## Derived knowledge

  Business rules (`blocked`, `requires_approval`), accounting policies
  (`policy`), and account roles (`account_role`) are derived by Datalog rules.

  Datalog decides facts and relationships. Elixir materializes journals and
  postings.
  """

  use ExDatalog.Schema

  # ------------------------------------------------------------------
  # Relations: per-event runtime facts
  # ------------------------------------------------------------------

  relation :event_type do
    field :event, :atom
    field :type, :atom
  end

  relation :event_amount_cents do
    field :event, :atom
    field :cents, :integer
  end

  relation :event_currency do
    field :event, :atom
    field :currency, :string
  end

  relation :event_fee_type do
    field :event, :atom
    field :fee_type, :atom
  end

  relation :event_entity_type do
    field :event, :atom
    field :entity_type, :atom
  end

  relation :event_product do
    field :event, :atom
    field :product, :atom
  end

  relation :event_account do
    field :event, :atom
    field :code, :string
  end

  relation :event_cash_account do
    field :event, :atom
    field :code, :string
  end

  relation :event_fee_income_account do
    field :event, :atom
    field :code, :string
  end

  relation :event_interest_expense_account do
    field :event, :atom
    field :code, :string
  end

  relation :event_destination_account do
    field :event, :atom
    field :code, :string
  end

  relation :sanctions_match do
    field :event, :atom
  end

  # ------------------------------------------------------------------
  # Relations: derived business rules
  # ------------------------------------------------------------------

  relation :blocked do
    field :event, :atom
  end

  relation :requires_approval do
    field :event, :atom
  end

  # ------------------------------------------------------------------
  # Relations: accounting policy selection
  # ------------------------------------------------------------------

  relation :policy do
    field :event, :atom
    field :policy, :atom
  end

  # ------------------------------------------------------------------
  # Relations: posting templates (static knowledge)
  # ------------------------------------------------------------------

  relation :template do
    field :policy, :atom
  end

  relation :template_posting do
    field :policy, :atom
    field :sequence, :integer
    field :direction, :atom
    field :role, :atom
    field :amount_var, :atom
    field :currency_var, :atom
  end

  relation :requires_dimension do
    field :policy, :atom
    field :dimension, :atom
  end

  relation :account_role_static do
    field :role, :atom
    field :code, :string
  end

  relation :account_role do
    field :event, :atom
    field :role, :atom
    field :code, :string
  end

  # ------------------------------------------------------------------
  # Static facts: templates and postings
  # ------------------------------------------------------------------

  fact template(:cash_deposit)
  fact template(:corporate_wire_fee)
  fact template(:retail_wire_fee)
  fact template(:internal_transfer)
  fact template(:interest_accrual)
  fact template(:refund_paid)

  # cash_deposit: debit cash, credit client liability
  facts :template_posting do
    row(:cash_deposit, 1, :debit, :cash_account, :event_amount, :event_currency)
    row(:cash_deposit, 2, :credit, :client_liability_account, :event_amount, :event_currency)
  end

  # corporate_wire_fee: debit client liability, credit fee income
  facts :template_posting do
    row(:corporate_wire_fee, 1, :debit, :client_liability_account, :event_amount, :event_currency)
    row(:corporate_wire_fee, 2, :credit, :fee_income_account, :event_amount, :event_currency)
  end

  # retail_wire_fee: same shape as corporate
  facts :template_posting do
    row(:retail_wire_fee, 1, :debit, :client_liability_account, :event_amount, :event_currency)
    row(:retail_wire_fee, 2, :credit, :fee_income_account, :event_amount, :event_currency)
  end

  # internal_transfer: debit destination, credit source (client liability)
  facts :template_posting do
    row(:internal_transfer, 1, :debit, :destination_account, :event_amount, :event_currency)
    row(:internal_transfer, 2, :credit, :client_liability_account, :event_amount, :event_currency)
  end

  # interest_accrual: debit interest expense, credit client liability
  facts :template_posting do
    row(:interest_accrual, 1, :debit, :interest_expense_account, :event_amount, :event_currency)
    row(:interest_accrual, 2, :credit, :client_liability_account, :event_amount, :event_currency)
  end

  # refund_paid: debit client liability, credit cash
  facts :template_posting do
    row(:refund_paid, 1, :debit, :client_liability_account, :event_amount, :event_currency)
    row(:refund_paid, 2, :credit, :cash_account, :event_amount, :event_currency)
  end

  # ------------------------------------------------------------------
  # Static facts: required dimensions
  # ------------------------------------------------------------------

  facts :requires_dimension do
    row(:cash_deposit, :entity_id)
    row(:cash_deposit, :currency)
    row(:cash_deposit, :account_code)
    row(:corporate_wire_fee, :entity_id)
    row(:corporate_wire_fee, :currency)
    row(:corporate_wire_fee, :account_code)
    row(:retail_wire_fee, :entity_id)
    row(:retail_wire_fee, :currency)
    row(:retail_wire_fee, :account_code)
    row(:internal_transfer, :entity_id)
    row(:internal_transfer, :currency)
    row(:internal_transfer, :account_code)
    row(:interest_accrual, :entity_id)
    row(:interest_accrual, :currency)
    row(:interest_accrual, :account_code)
    row(:refund_paid, :entity_id)
    row(:refund_paid, :currency)
    row(:refund_paid, :account_code)
  end

  # ------------------------------------------------------------------
  # Static facts: static account mappings (fallback when an event does
  # not carry the concrete account code for a role).
  # ------------------------------------------------------------------

  fact account_role_static(:interest_expense_account, "EXPENSES:INTEREST")

  # ------------------------------------------------------------------
  # Rules: business rules
  # ------------------------------------------------------------------

  rule blocked(E) do
    sanctions_match(E)
  end

  # Approval required for amounts strictly greater than 1,000,000 cents ($10,000).
  rule requires_approval(E) do
    event_amount_cents(E, A)
    gt(A, 1_000_000)
  end

  # ------------------------------------------------------------------
  # Rules: accounting policy selection
  # ------------------------------------------------------------------

  rule policy(E, :cash_deposit) do
    event_type(E, :deposit_received)
  end

  rule policy(E, :corporate_wire_fee) do
    event_type(E, :fee_assessed)
    event_fee_type(E, :wire_fee)
    event_entity_type(E, :corporate)
  end

  rule policy(E, :retail_wire_fee) do
    event_type(E, :fee_assessed)
    event_fee_type(E, :wire_fee)
    event_entity_type(E, :individual)
  end

  rule policy(E, :internal_transfer) do
    event_type(E, :transfer_settled)
  end

  rule policy(E, :interest_accrual) do
    event_type(E, :interest_accrued)
  end

  rule policy(E, :refund_paid) do
    event_type(E, :refund_issued)
  end

  # ------------------------------------------------------------------
  # Rules: account role resolution
  # ------------------------------------------------------------------

  rule account_role(E, :client_liability_account, C) do
    event_account(E, C)
  end

  rule account_role(E, :cash_account, C) do
    event_cash_account(E, C)
  end

  rule account_role(E, :fee_income_account, C) do
    event_fee_income_account(E, C)
  end

  rule account_role(E, :interest_expense_account, C) do
    event_interest_expense_account(E, C)
  end

  rule account_role(E, :destination_account, C) do
    event_destination_account(E, C)
  end

  # Static fallback for roles not carried by the event.
  rule account_role(E, R, C) do
    account_role_static(R, C)
    event_type(E, _)
  end

  # ------------------------------------------------------------------
  # Named queries
  # ------------------------------------------------------------------

  query :selected_policy do
    find P
    where policy(:evt, P)
  end

  query :account_roles do
    find R, C
    where account_role(:evt, R, C)
  end

  query :template_postings do
    find P, S, D, R, A, C
    where template_posting(P, S, D, R, A, C)
  end
end
