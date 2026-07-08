defmodule Logistiki.Accounting.Result do
  @moduledoc """
  The result of `Logistiki.process/1`.

  Captures the end-to-end outcome of the accounting pipeline for one business
  event: the selected policy, the generated journal and postings, the ledger
  backend result, projection updates, audit evidence id, warnings, and a human-
  readable explanation.
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
