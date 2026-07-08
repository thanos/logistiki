defmodule Logistiki.Knowledge.PolicySelector do
  @moduledoc """
  Selects the accounting policy for a normalized event using the knowledge layer.

  This is a thin façade over `Logistiki.Knowledge.KnowledgeBase` for callers
  that only need the policy decision.
  """

  alias Logistiki.Knowledge.KnowledgeBase

  @doc """
  Returns the accounting policy for `normalized_event`, or an error.

  ## Arguments

    * `normalized_event` — `%Logistiki.Event.Normalized{}`.

  ## Returns

    * `{:ok, atom()}` — the selected policy (e.g. `:cash_deposit`).
    * `{:error, :blocked_event}` — a business rule blocked the event.
    * `{:error, :approval_required}` — the event requires approval.
    * `{:error, :no_policy_found}` — no policy matched.
    * `{:error, term()}` — knowledge evaluation failed.

  ## Examples

      iex> {:ok, :cash_deposit} = Logistiki.Knowledge.PolicySelector.select(normalized_deposit)
      iex> {:error, :blocked_event} = Logistiki.Knowledge.PolicySelector.select(blocked_event)
      iex> {:error, :no_policy_found} = Logistiki.Knowledge.PolicySelector.select(unknown_event)
  """
  @doc since: "0.1.0"
  @spec select(Logistiki.Event.Normalized.t()) ::
          {:ok, atom()} | {:error, :blocked_event | :approval_required | :no_policy_found | term()}
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
