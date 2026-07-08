defmodule Logistiki.Knowledge.Result do
  @moduledoc """
  The outcome of evaluating the knowledge layer for a single business event.

  Captures the business-rule decisions, the selected accounting policy, the
  resolved posting template, the resolved account roles, and the required
  dimensions. The runtime turns this into a journal draft.

  ## Fields

    * `event_id` — `term() | nil` — the originating event id
    * `blocked` — `boolean()` — `true` when a business rule blocked the event
    * `requires_approval` — `boolean()` — `true` when approval is required
    * `policy` — `atom() | nil` — the selected accounting policy (e.g. `:cash_deposit`)
    * `template` — `atom() | nil` — the selected template (= the policy in v0.1.0)
    * `template_postings` — `[map()]` — ordered posting specs, each with
      `:sequence`, `:direction`, `:role`, `:amount_var`, `:currency_var`
    * `account_roles` — `%{atom() => String.t()}` — resolved role-to-code
      mappings (e.g. `%{cash_account: "ASSETS:CASH:USD:NOSTRO", ...}`)
    * `required_dimensions` — `[atom()]` — e.g. `[:entity_id, :currency, :account_code]`
    * `explanation` — `map()` — why the policy was selected / blocked

  ## Example

      %Logistiki.Knowledge.Result{
        event_id: "evt_001",
        blocked: false,
        requires_approval: false,
        policy: :cash_deposit,
        template: :cash_deposit,
        template_postings: [
          %{sequence: 1, direction: :debit, role: :cash_account, ...},
          %{sequence: 2, direction: :credit, role: :client_liability_account, ...}
        ],
        account_roles: %{
          cash_account: "ASSETS:CASH:USD:NOSTRO",
          client_liability_account: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING"
        },
        required_dimensions: [:entity_id, :currency, :account_code],
        explanation: %{reason: :unique, selected: :cash_deposit}
      }
  """

  @typedoc """
  The struct type. See the module documentation for field details and examples.
  """
  @type t :: %__MODULE__{
          event_id: term(),
          blocked: boolean(),
          requires_approval: boolean(),
          policy: atom() | nil,
          template: atom() | nil,
          template_postings: [map()],
          account_roles: %{atom() => String.t()},
          required_dimensions: [atom()],
          explanation: map()
        }

  defstruct event_id: nil,
            blocked: false,
            requires_approval: false,
            policy: nil,
            template: nil,
            template_postings: [],
            account_roles: %{},
            required_dimensions: [],
            explanation: %{}
end
