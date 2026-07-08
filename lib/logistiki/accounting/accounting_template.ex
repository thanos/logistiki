defmodule Logistiki.Accounting.AccountingTemplate do
  @moduledoc """
  A posting template: an ordered list of posting specs that a policy resolves
  into concrete postings.

  Each spec references a symbolic account `role`, a `direction` (`:debit` or
  `:credit`), and the amount/currency variables (always `:event_amount` and
  `:event_currency` in v0.1.0). The journal builder resolves the role to a
  concrete account code via the knowledge layer's `account_role` facts.

  ## Fields

    * `policy` — `atom()` — the policy this template belongs to (e.g.
      `:cash_deposit`)
    * `postings` — `[posting_spec()]` — ordered posting specifications

  ## Posting spec

  Each spec is a map with:

    * `:sequence` — `non_neg_integer()` — ordering within the journal
    * `:direction` — `:debit | :credit`
    * `:role` — `atom()` — symbolic account role (e.g. `:cash_account`)
    * `:amount_var` — `:event_amount` — always `:event_amount` in v0.1.0
    * `:currency_var` — `:event_currency` — always `:event_currency` in v0.1.0

  ## Example

      %Logistiki.Accounting.AccountingTemplate{
        policy: :cash_deposit,
        postings: [
          %{sequence: 1, direction: :debit, role: :cash_account, amount_var: :event_amount, currency_var: :event_currency},
          %{sequence: 2, direction: :credit, role: :client_liability_account, amount_var: :event_amount, currency_var: :event_currency}
        ]
      }
  """

  defstruct [:policy, :postings]

  @type posting_spec :: %{
          sequence: non_neg_integer(),
          direction: :debit | :credit,
          role: atom(),
          amount_var: :event_amount,
          currency_var: :event_currency
        }

  @typedoc """
  The struct type. See the module documentation for field details and examples.
  """
  @type t :: %__MODULE__{policy: atom(), postings: [posting_spec()]}
end
