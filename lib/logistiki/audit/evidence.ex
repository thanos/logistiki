defmodule Logistiki.Audit.Evidence do
  @moduledoc """
  A structured audit-evidence record.

  `Evidence` is the in-memory explanation that accompanies a processed event;
  it is persisted as one or more `Logistiki.Audit.AuditEvent` rows by
  `Logistiki.Audit`.
  """

  defstruct [:event_id, :journal_id, :stages, :explanation]

  @typedoc """
  The struct type. See the module documentation for field details and examples.
  """
  @type t :: %__MODULE__{
          event_id: term() | nil,
          journal_id: term() | nil,
          stages: [map()],
          explanation: map()
        }

  @doc "Builds an evidence record from a pipeline trace."
  @doc since: "0.1.0"
  def build(event_id, journal_id, stages, explanation) do
    %__MODULE__{event_id: event_id, journal_id: journal_id, stages: stages, explanation: explanation}
  end
end
