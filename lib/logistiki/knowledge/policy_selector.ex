defmodule Logistiki.Knowledge.PolicySelector do
  @moduledoc """
  Selects the accounting policy for a normalized event using the knowledge layer.

  This is a thin façade over `Logistiki.Knowledge.KnowledgeBase` for callers
  that only need the policy decision.
  """

  alias Logistiki.Knowledge.KnowledgeBase

  @doc "Returns `{:ok, policy}` or `{:error, reason}` for `normalized_event`."
  def select(normalized_event) do
    case KnowledgeBase.evaluate(normalized_event) do
      {:ok, %{blocked: true}} -> {:error, :blocked_event}
      {:ok, %{requires_approval: true}} -> {:error, :approval_required}
      {:ok, %{policy: nil}} -> {:error, :no_policy_found}
      {:ok, %{policy: policy}} -> {:ok, policy}
      {:error, reason} -> {:error, reason}
    end
  end
end
