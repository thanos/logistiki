defmodule Logistiki.Knowledge.Query do
  @moduledoc """
  Helpers for querying materialized `ExDatalog.Knowledge` for Logistiki facts.

  The event under evaluation is always identified by the atom `:evt` inside the
  Datalog program (see `Logistiki.Knowledge.Facts.event_id/0`).
  """

  alias ExDatalog.Knowledge
  alias Logistiki.Knowledge.Facts

  @doc """
  Returns all derived `policy` facts for the current event.

  ## Arguments

    * `knowledge` — `%ExDatalog.Knowledge{}` — materialized knowledge.

  ## Returns

    * `[atom()]` — the policy atoms derived for `:evt` (e.g. `[:cash_deposit]`).
      Empty list if no policy matched.

  ## Examples

      iex> Logistiki.Knowledge.Query.policies(knowledge)
      [:cash_deposit]
  """
  @doc since: "0.1.0"
  @spec policies(ExDatalog.Knowledge.t()) :: [atom()]
  def policies(knowledge) do
    knowledge
    |> Knowledge.get("policy")
    |> Enum.filter(fn {evt, _policy} -> evt == Facts.event_id() end)
    |> Enum.map(fn {_evt, policy} -> policy end)
  end

  @doc """
  True when the event is blocked by a business rule.

  ## Arguments

    * `knowledge` — `%ExDatalog.Knowledge{}`.

  ## Returns

    * `boolean()` — `true` if `blocked(:evt)` was derived.

  ## Examples

      iex> Logistiki.Knowledge.Query.blocked?(knowledge)
      false
  """
  @doc since: "0.1.0"
  @spec blocked?(ExDatalog.Knowledge.t()) :: boolean()
  def blocked?(knowledge) do
    target = {Facts.event_id()}

    Knowledge.get(knowledge, "blocked")
    |> Enum.any?(&(&1 == target))
  end

  @doc """
  True when the event requires approval.

  ## Arguments

    * `knowledge` — `%ExDatalog.Knowledge{}`.

  ## Returns

    * `boolean()` — `true` if `requires_approval(:evt)` was derived.

  ## Examples

      iex> Logistiki.Knowledge.Query.requires_approval?(knowledge)
      false
  """
  @doc since: "0.1.0"
  @spec requires_approval?(ExDatalog.Knowledge.t()) :: boolean()
  def requires_approval?(knowledge) do
    target = {Facts.event_id()}

    Knowledge.get(knowledge, "requires_approval")
    |> Enum.any?(&(&1 == target))
  end

  @doc """
  Returns all resolved `account_role` facts for the current event.

  ## Arguments

    * `knowledge` — `%ExDatalog.Knowledge{}`.

  ## Returns

    * `%{atom() => String.t()}` — role-to-account-code map (e.g.
      `%{cash_account: "ASSETS:CASH:USD:NOSTRO", ...}`).

  ## Examples

      iex> Logistiki.Knowledge.Query.account_roles(knowledge)
      %{cash_account: "ASSETS:CASH:USD:NOSTRO", client_liability_account: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING"}
  """
  @doc since: "0.1.0"
  @spec account_roles(ExDatalog.Knowledge.t()) :: %{atom() => String.t()}
  def account_roles(knowledge) do
    knowledge
    |> Knowledge.get("account_role")
    |> Enum.filter(fn {evt, _role, _code} -> evt == Facts.event_id() end)
    |> Enum.into(%{}, fn {_evt, role, code} -> {role, code} end)
  end

  @doc """
  Returns all `template_posting` facts (for every policy).

  ## Arguments

    * `knowledge` — `%ExDatalog.Knowledge{}`.

  ## Returns

    * `[map()]` — posting specs with `:policy`, `:sequence`, `:direction`,
      `:role`, `:amount_var`, `:currency_var`.

  ## Examples

      iex> Logistiki.Knowledge.Query.template_postings(knowledge) |> hd()
      %{policy: :cash_deposit, sequence: 1, direction: :debit, role: :cash_account, amount_var: :event_amount, currency_var: :event_currency}
  """
  @doc since: "0.1.0"
  @spec template_postings(ExDatalog.Knowledge.t()) :: [map()]
  def template_postings(knowledge) do
    Knowledge.get(knowledge, "template_posting")
    |> Enum.map(fn {policy, seq, direction, role, amount_var, currency_var} ->
      %{
        policy: policy,
        sequence: seq,
        direction: direction,
        role: role,
        amount_var: amount_var,
        currency_var: currency_var
      }
    end)
  end

  @doc """
  Returns all `requires_dimension` facts grouped by policy.

  ## Arguments

    * `knowledge` — `%ExDatalog.Knowledge{}`.

  ## Returns

    * `%{atom() => [atom()]}` — policy-to-dimensions map (e.g.
      `%{cash_deposit: [:entity_id, :currency, :account_code]}`).

  ## Examples

      iex> Logistiki.Knowledge.Query.required_dimensions(knowledge)
      %{cash_deposit: [:entity_id, :currency, :account_code]}
  """
  @doc since: "0.1.0"
  @spec required_dimensions(ExDatalog.Knowledge.t()) :: %{atom() => [atom()]}
  def required_dimensions(knowledge) do
    Knowledge.get(knowledge, "requires_dimension")
    |> Enum.into(%{}, fn {policy, dimension} -> {policy, dimension} end)
    |> Enum.group_by(fn {policy, _dim} -> policy end, fn {_policy, dim} -> dim end)
  end
end
