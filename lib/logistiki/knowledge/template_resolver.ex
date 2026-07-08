defmodule Logistiki.Knowledge.TemplateResolver do
  @moduledoc """
  Resolves the posting template for a selected accounting policy.

  A template is a list of posting specs (`%{sequence, direction, role,
  amount_var, currency_var}`). The journal builder turns a template plus
  resolved account roles into concrete postings.
  """

  alias Logistiki.Knowledge.KnowledgeBase
  alias Logistiki.Knowledge.Result

  @doc """
  Resolves the template postings for `normalized_event`'s selected policy.

  ## Arguments

    * `normalized_event` — `%Logistiki.Event.Normalized{}`.

  ## Returns

    * `{:ok, %Result{}, [posting_spec]}` — the full knowledge result and the
      ordered posting specs for the selected policy.
    * `{:error, :no_template_found}` — the selected policy has no template.
    * `{:error, term()}` — knowledge evaluation failed.

  ## Examples

      iex> {:ok, result, postings} = Logistiki.Knowledge.TemplateResolver.resolve(normalized_deposit)
      iex> length(postings)
      2
      iex> hd(postings).role
      :cash_account
  """
  @doc since: "0.1.0"
  @spec resolve(Logistiki.Event.Normalized.t()) ::
          {:ok, Result.t(), [map()]} | {:error, :no_template_found | term()}
  def resolve(normalized_event) do
    case KnowledgeBase.evaluate(normalized_event) do
      {:ok, %Result{template_postings: []}} -> {:error, :no_template_found}
      {:ok, %Result{template_postings: postings} = result} -> {:ok, result, postings}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Resolves the concrete account code for `role` from `account_roles`.

  ## Arguments

    * `account_roles` — `map()` — the role-to-code map from a `Result`
      (e.g. `%{cash_account: "ASSETS:CASH:USD:NOSTRO"}`).
    * `role` — `atom()` — the symbolic role (e.g. `:cash_account`).

  ## Returns

    * `{:ok, String.t()}` — the resolved account code.
    * `{:error, {:missing_account_role, role}}` — no mapping for this role.

  ## Examples

      iex> {:ok, "ASSETS:CASH:USD:NOSTRO"} = Logistiki.Knowledge.TemplateResolver.resolve_account_role(
      ...>   %{cash_account: "ASSETS:CASH:USD:NOSTRO"}, :cash_account
      ...> )
      iex> {:error, {:missing_account_role, :unknown_role}} = Logistiki.Knowledge.TemplateResolver.resolve_account_role(%{}, :unknown_role)
  """
  @doc since: "0.1.0"
  @spec resolve_account_role(map(), atom()) ::
          {:ok, String.t()} | {:error, {:missing_account_role, atom()}}
  def resolve_account_role(account_roles, role) when is_map(account_roles) do
    case Map.fetch(account_roles, role) do
      {:ok, code} -> {:ok, code}
      :error -> {:error, {:missing_account_role, role}}
    end
  end
end
