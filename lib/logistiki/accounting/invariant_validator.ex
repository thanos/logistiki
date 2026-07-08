defmodule Logistiki.Accounting.InvariantValidator do
  @moduledoc """
  Enforces hard accounting invariants in deterministic Elixir.

  These checks **never** depend on Datalog. Datalog may say what should happen;
  Elixir enforces what must always be true.

  ## Invariants enforced

    * a journal has at least two postings
    * postings reference existing accounts
    * postings target leaf, active, posting-allowed accounts
    * amounts are positive
    * currencies are present
    * debits equal credits per currency
    * idempotency key is unique among posted journals
    * frozen/closed accounts reject postings
    * reversal exactly negates the original postings
    * posted journals are immutable (checked at the context layer)

  Returns `:ok` or `{:error, %Logistiki.Error{}}`.
  """

  import Ecto.Query

  alias Logistiki.Accounting.Journal
  alias Logistiki.Accounting.Posting
  alias Logistiki.Error
  alias Logistiki.Repo
  alias Logistiki.VirtualAccounts

  @doc "Validates a list of posting changesets (or maps) for the invariants that don't require the DB."
  def validate_postings(postings) do
    with :ok <- require_min_two_postings(postings),
         :ok <- require_positive_amounts(postings),
         :ok <- require_currencies(postings),
         :ok <- require_balanced_per_currency(postings) do
      require_valid_directions(postings)
    end
  end

  @doc "Validates that each posting targets an existing, leaf, active, posting-allowed account."
  def validate_accounts(postings) do
    codes = Enum.map(postings, &account_code/1) |> Enum.uniq()

    with {:ok, accounts_by_code} <- fetch_accounts(codes) do
      Enum.reduce_while(postings, :ok, fn posting, :ok ->
        validate_single_account(posting, accounts_by_code)
      end)
    end
  end

  defp validate_single_account(posting, accounts_by_code) do
    case validate_account(posting, accounts_by_code) do
      :ok -> {:cont, :ok}
      {:error, _} = err -> {:halt, err}
    end
  end

  @doc "Validates that the idempotency key is unique among posted journals."
  def validate_idempotency(nil), do: :ok

  def validate_idempotency(idempotency_key) do
    exists =
      from(j in Journal,
        where: j.idempotency_key == ^idempotency_key and j.status == "posted"
      )
      |> Repo.exists?()

    if exists do
      {:error,
       Error.new(:duplicate_idempotency_key,
         message: "a posted journal with idempotency key #{inspect(idempotency_key)} already exists",
         stage: :invariant_validation
       )}
    else
      :ok
    end
  end

  @doc "Validates that `reversal_postings` exactly negate `original_postings`."
  def validate_reversal(original_postings, reversal_postings) when is_list(original_postings) do
    if length(original_postings) == length(reversal_postings) and
         Enum.all?(Enum.zip(original_postings, reversal_postings), fn {orig, rev} ->
           account_code(orig) == account_code(rev) and
             Decimal.equal?(amount(orig), amount(rev)) and
             opposite(direction(orig)) == direction(rev) and
             currency(orig) == currency(rev)
         end) do
      :ok
    else
      {:error,
       Error.new(:unbalanced_journal,
         message: "reversal postings do not exactly negate the original postings",
         stage: :invariant_validation
       )}
    end
  end

  @doc "Validates a journal's full invariant set (postings + accounts + idempotency)."
  def validate(%Journal{idempotency_key: key}, postings) do
    with :ok <- validate_postings(postings),
         :ok <- validate_accounts(postings) do
      validate_idempotency(key)
    end
  end

  # ------------------------------------------------------------------
  # Individual invariants
  # ------------------------------------------------------------------

  defp require_min_two_postings(postings) when length(postings) < 2 do
    {:error,
     Error.new(:unbalanced_journal,
       message: "a journal requires at least two postings",
       stage: :invariant_validation
     )}
  end

  defp require_min_two_postings(_), do: :ok

  defp require_positive_amounts(postings) do
    Enum.reduce_while(postings, :ok, fn p, :ok ->
      a = amount(p)

      if not is_nil(a) and Decimal.positive?(a) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Error.new(:unbalanced_journal,
            message: "posting amounts must be positive",
            details: %{account_code: account_code(p), amount: a},
            stage: :invariant_validation
          )}}
      end
    end)
  end

  defp require_currencies(postings) do
    Enum.reduce_while(postings, :ok, fn p, :ok ->
      if is_binary(currency(p)) and currency(p) != "" do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Error.new(:unbalanced_journal,
            message: "postings must specify a currency",
            details: %{account_code: account_code(p)},
            stage: :invariant_validation
          )}}
      end
    end)
  end

  defp require_valid_directions(postings) do
    Enum.reduce_while(postings, :ok, fn p, :ok ->
      d = direction(p)

      if d in ["debit", "credit"] do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Error.new(:unbalanced_journal,
            message: "posting direction must be debit or credit",
            details: %{account_code: account_code(p), direction: d},
            stage: :invariant_validation
          )}}
      end
    end)
  end
  defp require_balanced_per_currency(postings) do
    postings
    |> Enum.group_by(&currency/1)
    |> Enum.reduce_while(:ok, fn {currency, group}, :ok ->
      {debits, credits} = debit_credit_totals(group)

      if Decimal.equal?(debits, credits) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          Error.new(:unbalanced_journal,
            message: "journal debits and credits do not balance for #{currency}",
            details: %{currency: currency, debits: Decimal.to_string(debits), credits: Decimal.to_string(credits)},
            stage: :invariant_validation
          )}}
      end
    end)
  end

  defp debit_credit_totals(group) do
    Enum.reduce(group, {Decimal.new(0), Decimal.new(0)}, fn p, {debits, credits} ->
      if direction(p) == "debit",
        do: {Decimal.add(debits, amount(p)), credits},
        else: {debits, Decimal.add(credits, amount(p))}
    end)
  end

  defp fetch_accounts(codes) when codes == [] do
    {:ok, %{}}
  end

  defp fetch_accounts(codes) do
    accounts = VirtualAccounts.list_accounts()

    by_code =
      Enum.into(accounts, %{}, fn a ->
        {a.code, a}
      end)

    missing = Enum.reject(codes, &Map.has_key?(by_code, &1))

    if missing == [] do
      {:ok, by_code}
    else
      {:error,
       Error.new(:account_not_found,
         message: "accounts not found: #{Enum.join(missing, ", ")}",
         details: %{missing: missing},
         stage: :invariant_validation
       )}
    end
  end

  defp validate_account(posting, accounts_by_code) do
    code = account_code(posting)
    account = Map.get(accounts_by_code, code)

    cond do
      is_nil(account) ->
        {:error,
         Error.new(:account_not_found,
           message: "account #{inspect(code)} does not exist",
           details: %{account_code: code},
           stage: :invariant_validation
         )}

      not VirtualAccounts.posting_account?(account) ->
        {:error,
         Error.new(:account_not_postable,
           message: "account #{inspect(code)} is not a posting account (leaf, active, posting-allowed)",
           details: %{account_code: code, status: account.status, posting_allowed: account.posting_allowed},
           stage: :invariant_validation
         )}

      true ->
        :ok
    end
  end

  # ------------------------------------------------------------------
  # Accessors that work for both changesets and structs
  # ------------------------------------------------------------------

  defp account_code(%Ecto.Changeset{} = cs), do: Ecto.Changeset.get_field(cs, :account_code)
  defp account_code(%Posting{} = p), do: p.account_code
  defp account_code(%{account_code: c}), do: c

  defp direction(%Ecto.Changeset{} = cs), do: Ecto.Changeset.get_field(cs, :debit_credit)
  defp direction(%Posting{} = p), do: p.debit_credit
  defp direction(%{debit_credit: d}), do: d

  defp amount(%Ecto.Changeset{} = cs), do: Ecto.Changeset.get_field(cs, :amount)
  defp amount(%Posting{} = p), do: p.amount
  defp amount(%{amount: a}), do: a

  defp currency(%Ecto.Changeset{} = cs), do: Ecto.Changeset.get_field(cs, :currency)
  defp currency(%Posting{} = p), do: p.currency
  defp currency(%{currency: c}), do: c

  defp opposite("debit"), do: "credit"
  defp opposite("credit"), do: "debit"
end
