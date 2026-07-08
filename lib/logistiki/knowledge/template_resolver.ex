defmodule Logistiki.Knowledge.TemplateResolver do
  @moduledoc """
  Resolves the posting template for a selected accounting policy.

  A template is a list of posting specs (`%{sequence, direction, role,
  amount_var, currency_var}`). The journal builder turns a template plus
  resolved account roles into concrete postings.
  """

  alias Logistiki.Knowledge.KnowledgeBase
  alias Logistiki.Knowledge.Result

  @doc "Resolves the template postings for `normalized_event`'s selected policy."
  def resolve(normalized_event) do
    case KnowledgeBase.evaluate(normalized_event) do
      {:ok, %Result{template_postings: []}} -> {:error, :no_template_found}
      {:ok, %Result{template_postings: postings} = result} -> {:ok, result, postings}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Resolves the concrete account code for `role` from `account_roles`."
  def resolve_account_role(account_roles, role) when is_map(account_roles) do
    case Map.fetch(account_roles, role) do
      {:ok, code} -> {:ok, code}
      :error -> {:error, {:missing_account_role, role}}
    end
  end
end
