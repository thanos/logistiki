defmodule Logistiki.Knowledge.Result do
  @moduledoc """
  The outcome of evaluating the knowledge layer for a single business event.

  Captures the business-rule decisions, the selected accounting policy, the
  resolved posting template, the resolved account roles, and the required
  dimensions. The runtime turns this into a journal draft.
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
