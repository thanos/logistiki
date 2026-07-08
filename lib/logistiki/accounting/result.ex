defmodule Logistiki.Accounting.Result do
  @moduledoc """
  The result of `Logistiki.process/1`.

  Captures the end-to-end outcome of the accounting pipeline for one business
  event: the selected policy, the generated journal and postings, the ledger
  backend result, projection updates, audit evidence id, warnings, and a human-
  readable explanation.

  ## Fields

    * `event_id` — `term() | nil` — the originating event id
    * `policy` — `atom() | nil` — the selected accounting policy (e.g.
      `:cash_deposit`); `nil` for no-accounting-impact events
    * `template` — `atom() | nil` — the selected template
    * `journal` — `Logistiki.Accounting.Journal.t() | nil` — the posted journal;
      `nil` for no-accounting-impact events
    * `postings` — `[Logistiki.Accounting.Posting.t()]` — the journal's postings
    * `ledger_result` — `Logistiki.Ledger.Result.t() | nil` — the backend result
    * `projection_updates` — `map()` — balance updates keyed by account code
    * `audit_evidence_id` — `term() | nil` — the event id for audit trail lookup
    * `warnings` — `[term()]` — non-fatal warnings
    * `explanation` — `map()` — the full pipeline explanation (policy, template,
      account roles, knowledge explanation, reason)

  ## Example

      %Logistiki.Accounting.Result{
        event_id: "evt_001",
        policy: :cash_deposit,
        template: :cash_deposit,
        journal: %Logistiki.Accounting.Journal{status: "posted", ...},
        postings: [%Posting{...}, %Posting{...}],
        ledger_result: %Logistiki.Ledger.Result{backend: Logistiki.Ledger.Simulation, status: :ok},
        audit_evidence_id: "evt_001",
        warnings: [],
        explanation: %{policy: :cash_deposit, template: :cash_deposit, account_roles: %{...}}
      }

  ## No-accounting-impact result

      %Logistiki.Accounting.Result{
        event_id: "evt_007",
        policy: nil,
        journal: nil,
        postings: [],
        explanation: %{reason: :no_accounting_impact}
      }
  """

  @typedoc """
  The struct type. See the module documentation for field details and examples.
  """
  @type t :: %__MODULE__{
          event_id: term() | nil,
          policy: atom() | nil,
          template: atom() | nil,
          journal: Logistiki.Accounting.Journal.t() | nil,
          postings: [Logistiki.Accounting.Posting.t()],
          ledger_result: term() | nil,
          projection_updates: map(),
          audit_evidence_id: term() | nil,
          warnings: [term()],
          explanation: map()
        }

  defstruct event_id: nil,
            policy: nil,
            template: nil,
            journal: nil,
            postings: [],
            ledger_result: nil,
            projection_updates: %{},
            audit_evidence_id: nil,
            warnings: [],
            explanation: %{}
end
