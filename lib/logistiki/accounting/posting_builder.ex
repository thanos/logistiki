defmodule Logistiki.Accounting.PostingBuilder do
  @moduledoc """
  Builds concrete postings from a posting template and resolved account roles.

  The journal builder calls this module with:

    * the template postings (from the knowledge layer)
    * the resolved account roles (role -> account code)
    * the event amount and currency
    * the journal id the postings belong to

  Each template posting spec is turned into a `%Logistiki.Accounting.Posting`
  changeset. Symbolic roles are resolved to account codes; missing roles
  produce an error.
  """

  alias Logistiki.Accounting.Posting
  alias Logistiki.Error

  @doc """
  Builds draft posting structs from `template_postings`, `account_roles`,
  `amount`, and `currency`.

  Returns `{:ok, [%Posting{}]}` or `{:error, %Logistiki.Error{}}`. The postings
  carry `account_code`, `debit_credit`, `amount`, `currency`, `sequence`, and
  role metadata but no `virtual_account_id` or `journal_id` yet — the ledger
  backend resolves and sets those on persistence.
  """
  def build(template_postings, account_roles, amount, currency, _journal_id) do
    with :ok <- require_amount(amount),
         :ok <- require_currency(currency) do
      template_postings
      |> Enum.sort_by(& &1.sequence)
      |> Enum.reduce_while({:ok, []}, fn spec, {:ok, acc} ->
        case build_posting(spec, account_roles, amount, currency) do
          {:ok, posting} -> {:cont, {:ok, acc ++ [posting]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp build_posting(spec, account_roles, amount, currency) do
    case resolve_role(account_roles, spec.role) do
      {:ok, account_code} ->
        {:ok,
         %Posting{
           account_code: account_code,
           debit_credit: Atom.to_string(spec.direction),
           amount: amount,
           currency: currency,
           sequence: spec.sequence,
           metadata: %{role: Atom.to_string(spec.role)}
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp require_amount(nil) do
    {:error, %Error{code: :invalid_template, message: "event amount is missing", stage: :posting_builder}}
  end

  defp require_amount(%Decimal{} = a) do
    if Decimal.positive?(a) do
      :ok
    else
      {:error, %Error{code: :invalid_template, message: "event amount must be positive", stage: :posting_builder}}
    end
  end

  defp require_currency(nil) do
    {:error, %Error{code: :invalid_template, message: "event currency is missing", stage: :posting_builder}}
  end

  defp require_currency(_), do: :ok

  defp resolve_role(account_roles, role) do
    case Map.fetch(account_roles, role) do
      {:ok, code} when is_binary(code) -> {:ok, code}
      {:ok, nil} -> {:error, missing_role(role)}
      :error -> {:error, missing_role(role)}
    end
  end

  defp missing_role(role) do
    %Error{
      code: :account_not_found,
      message: "no account mapping for role #{inspect(role)}",
      details: %{role: role},
      stage: :posting_builder
    }
  end

  @doc "Builds reversal postings that exactly negate `postings` (flip direction, keep amount)."
  def build_reversals(postings, _reversal_journal_id) do
    Enum.map(postings, fn p ->
      %Posting{
        account_code: p.account_code,
        debit_credit: opposite(p.debit_credit),
        amount: p.amount,
        currency: p.currency,
        sequence: p.sequence,
        memo: "reversal",
        metadata: Map.put(p.metadata || %{}, "reversal_of_posting", p.id)
      }
    end)
  end

  defp opposite("debit"), do: "credit"
  defp opposite("credit"), do: "debit"
end
