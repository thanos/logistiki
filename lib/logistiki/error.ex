defmodule Logistiki.Error do
  @moduledoc """
  Structured errors returned across the accounting pipeline.

  Every `{:error, _}` returned by Logistiki is a `%Logistiki.Error{}` so callers
  can dispatch on `code` and `stage` programmatically.

  ## Common error codes

    * `:invalid_event` — the event failed normalization or is missing required fields
    * `:blocked_event` — a business rule blocked the event
    * `:approval_required` — the event requires approval before processing
    * `:no_policy_found` — no accounting policy matched the event
    * `:ambiguous_policy` — more than one policy matched the event
    * `:no_template_found` — the selected policy has no posting template
    * `:invalid_template` — the template could not be turned into postings
    * `:account_not_found` — a resolved account code does not exist
    * `:account_not_postable` — a posting targets a non-leaf / frozen / closed account
    * `:unbalanced_journal` — debits and credits do not balance per currency
    * `:duplicate_idempotency_key` — a journal with this idempotency key is already posted
    * `:immutable_journal` — an attempt was made to mutate a posted journal
    * `:backend_error` — the ledger backend returned an error
    * `:projection_error` — a projection could not be computed
  """

  @type stage ::
          :normalization
          | :business_rules
          | :policy_selection
          | :template_resolution
          | :posting_builder
          | :journal_builder
          | :invariant_validation
          | :ledger_backend
          | :projection
          | :persistence

  @type t :: %__MODULE__{
          code: atom(),
          message: String.t(),
          details: map(),
          stage: stage() | nil
        }

  defstruct [:code, :message, :stage, details: %{}]

  @doc "Builds an error from a code and optional keyword list."
  def new(code, opts \\ []) do
    %__MODULE__{
      code: code,
      message: Keyword.get(opts, :message, to_string(code)),
      details: Keyword.get(opts, :details, %{}),
      stage: Keyword.get(opts, :stage)
    }
  end
end
