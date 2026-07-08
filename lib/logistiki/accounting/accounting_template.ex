defmodule Logistiki.Accounting.AccountingTemplate do
  @moduledoc """
  A posting template: an ordered list of posting specs that a policy resolves
  into concrete postings.

  Each spec references a symbolic account `role`, a `direction` (`:debit` or
  `:credit`), and the amount/currency variables (always `:event_amount` and
  `:event_currency` in v0.1.0). The journal builder resolves the role to a
  concrete account code via the knowledge layer's `account_role` facts.
  """

  defstruct [:policy, :postings]

  @type posting_spec :: %{
          sequence: non_neg_integer(),
          direction: :debit | :credit,
          role: atom(),
          amount_var: :event_amount,
          currency_var: :event_currency
        }

  @type t :: %__MODULE__{policy: atom(), postings: [posting_spec()]}
end
