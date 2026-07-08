defmodule Logistiki.Accounting.PostingBuilder do
  @moduledoc """
  Builds concrete postings from a posting template and resolved account roles.

  The journal builder calls this module with:

    * the template postings (from the knowledge layer)
    * the resolved account roles (role -> account code)
    * the event amount and currency
    * the journal id the postings belong to

  Each template posting spec is turned into a `%Logistiki.Accounting.Posting`
  struct. Symbolic roles are resolved to account codes; missing roles produce
  an error.
  """

  alias Logistiki.Accounting.Posting
  alias Logistiki.Error

  @doc """
  Builds draft posting structs from `template_postings`, `account_roles`,
  `amount`, and `currency`.

  The postings carry `account_code`, `debit_credit`, `amount`, `currency`,
  `sequence`, and role metadata but no `virtual_account_id` or `journal_id`
  yet — the ledger backend resolves and sets those on persistence.

  ## Arguments

    * `template_postings` — `[map()]` — posting specs from the knowledge layer,
      each with `:sequence`, `:direction`, `:role`, `:amount_var`,
      `:currency_var`.
    * `account_roles` — `%{atom() => String.t()}` — resolved role-to-code map
      (e.g. `%{cash_account: "ASSETS:CASH:USD:NOSTRO"}`).
    * `amount` — `Decimal.t()` — the event amount (e.g.
      `Decimal.new("1000.00")`).
    * `currency` — `String.t()` — the event currency (e.g. `"USD"`).
    * `_journal_id` — `term()` — unused in v0.1.0 (postings are linked on
      persistence).

  ## Returns

    * `{:ok, [%Posting{}]}` — the built posting structs, sorted by sequence.
    * `{:error, %Error{code: :invalid_template}}` — amount or currency is
      missing/invalid.
    * `{:error, %Error{code: :account_not_found}}` — a role could not be
      resolved to an account code.

  ## Examples

      iex> {:ok, postings} = Logistiki.Accounting.PostingBuilder.build(
      ...>   [%{sequence: 1, direction: :debit, role: :cash_account, amount_var: :event_amount, currency_var: :event_currency},
      ...>    %{sequence: 2, direction: :credit, role: :client_liability_account, amount_var: :event_amount, currency_var: :event_currency}],
      ...>   %{cash_account: "ASSETS:CASH:USD:NOSTRO", client_liability_account: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING"},
      ...>   Decimal.new("1000.00"), "USD", nil
      ...> )
      iex> length(postings)
      2
      iex> hd(postings).account_code
      "ASSETS:CASH:USD:NOSTRO"
  """
  @doc since: "0.1.0"
  @spec build([map()], %{atom() => String.t()}, Decimal.t(), String.t(), term()) ::
          {:ok, [Posting.t()]} | {:error, Error.t()}
  def build(template_postings, account_roles, amount, currency, _journal_id) do
    with :ok <- require_amount(amount),
         :ok <- require_currency(currency) do
      template_postings
      |> Enum.sort_by(& &1.sequence)
      |> Enum.reduce_while({:ok, []}, fn spec, {:ok, acc} ->
        append_posting(spec, acc, account_roles, amount, currency)
      end)
    end
  end

  # Appends a single posting to the accumulator, halting on error.
  defp append_posting(spec, acc, account_roles, amount, currency) do
    case build_posting(spec, account_roles, amount, currency) do
      {:ok, posting} -> {:cont, {:ok, acc ++ [posting]}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  # Builds a single posting struct from a template spec by resolving the role.
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

  # Validates that the amount is present and positive.
  defp require_amount(nil) do
    {:error,
     %Error{code: :invalid_template, message: "event amount is missing", stage: :posting_builder}}
  end

  defp require_amount(%Decimal{} = a) do
    if Decimal.positive?(a) do
      :ok
    else
      {:error,
       %Error{
         code: :invalid_template,
         message: "event amount must be positive",
         stage: :posting_builder
       }}
    end
  end

  # Validates that the currency is present.
  defp require_currency(nil) do
    {:error,
     %Error{code: :invalid_template, message: "event currency is missing", stage: :posting_builder}}
  end

  defp require_currency(_), do: :ok

  # Resolves a symbolic role to an account code from the roles map.
  defp resolve_role(account_roles, role) do
    case Map.fetch(account_roles, role) do
      {:ok, code} when is_binary(code) -> {:ok, code}
      {:ok, nil} -> {:error, missing_role(role)}
      :error -> {:error, missing_role(role)}
    end
  end

  # Builds an error for a missing account role.
  defp missing_role(role) do
    %Error{
      code: :account_not_found,
      message: "no account mapping for role #{inspect(role)}",
      details: %{role: role},
      stage: :posting_builder
    }
  end

  @doc """
  Builds reversal postings that exactly negate `postings` (flip direction,
  keep amount, currency, account, and sequence).

  ## Arguments

    * `postings` — `[Posting.t()]` — the original postings to reverse.
    * `_reversal_journal_id` — `term()` — unused in v0.1.0.

  ## Returns

    * `[Posting.t()]` — reversal posting structs with flipped `debit_credit`,
      `memo: "reversal"`, and `reversal_of_posting` in metadata.

  ## Examples

      iex> reversals = Logistiki.Accounting.PostingBuilder.build_reversals([%Posting{account_code: "A", debit_credit: "debit", amount: Decimal.new("100"), currency: "USD", sequence: 1}], nil)
      iex> hd(reversals).debit_credit
      "credit"
      iex> hd(reversals).memo
      "reversal"
  """
  @doc since: "0.1.0"
  @spec build_reversals([Posting.t()], term()) :: [Posting.t()]
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

  # Returns the opposite direction: debit <-> credit.
  defp opposite("debit"), do: "credit"
  defp opposite("credit"), do: "debit"
end
