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

  @doc """
  Validates a list of posting changesets (or maps) for the invariants that
  don't require the DB.

  Checks: at least two postings, positive amounts, currencies present, valid
  directions, and debits equal credits per currency.

  ## Arguments

    * `postings` — `[Posting.t()]` or `[Ecto.Changeset.t()]` — the postings to
      validate.

  ## Returns

    * `:ok` — all invariants hold.
    * `{:error, %Error{code: :unbalanced_journal}}` — an invariant was violated.

  ## Examples

      iex> Logistiki.Accounting.InvariantValidator.validate_postings([
      ...>   %Posting{account_code: "A", debit_credit: "debit", amount: Decimal.new("100"), currency: "USD", sequence: 1},
      ...>   %Posting{account_code: "B", debit_credit: "credit", amount: Decimal.new("100"), currency: "USD", sequence: 2}
      ...> ])
      :ok

      iex> {:error, %{code: :unbalanced_journal}} = Logistiki.Accounting.InvariantValidator.validate_postings([
      ...>   %Posting{account_code: "A", debit_credit: "debit", amount: Decimal.new("100"), currency: "USD", sequence: 1}
      ...> ])
  """
  @doc since: "0.1.0"
  @spec validate_postings([Posting.t() | Ecto.Changeset.t() | map()]) :: :ok | {:error, Error.t()}
  def validate_postings(postings) do
    with :ok <- require_min_two_postings(postings),
         :ok <- require_positive_amounts(postings),
         :ok <- require_currencies(postings),
         :ok <- require_balanced_per_currency(postings) do
      require_valid_directions(postings)
    end
  end

  @doc """
  Validates that each posting targets an existing, leaf, active, posting-
  allowed account.

  ## Arguments

    * `postings` — `[Posting.t()]` or `[map()]` — the postings to validate.

  ## Returns

    * `:ok` — all accounts are valid posting targets.
    * `{:error, %Error{code: :account_not_found}}` — an account code doesn't exist.
    * `{:error, %Error{code: :account_not_postable}}` — an account is not a leaf
      posting account.

  ## Examples

      iex> Logistiki.Accounting.InvariantValidator.validate_accounts([
      ...>   %Posting{account_code: "ASSETS:CASH:USD:NOSTRO", debit_credit: "debit", amount: Decimal.new("100"), currency: "USD", sequence: 1},
      ...>   %Posting{account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", debit_credit: "credit", amount: Decimal.new("100"), currency: "USD", sequence: 2}
      ...> ])
      :ok
  """
  @doc since: "0.1.0"
  @spec validate_accounts([Posting.t() | map()]) :: :ok | {:error, Error.t()}
  def validate_accounts(postings) do
    codes = Enum.map(postings, &account_code/1) |> Enum.uniq()

    with {:ok, accounts_by_code} <- fetch_accounts(codes) do
      Enum.reduce_while(postings, :ok, fn posting, :ok ->
        validate_single_account(posting, accounts_by_code)
      end)
    end
  end

  # Validates a single posting's account, returning :cont or :halt for reduce_while.
  defp validate_single_account(posting, accounts_by_code) do
    case validate_account(posting, accounts_by_code) do
      :ok -> {:cont, :ok}
      {:error, _} = err -> {:halt, err}
    end
  end

  @doc """
  Validates that the idempotency key is unique among posted journals.

  ## Arguments

    * `idempotency_key` — `String.t() | nil` — the key to check. `nil` always
      passes.

  ## Returns

    * `:ok` — no posted journal with this key exists.
    * `{:error, %Error{code: :duplicate_idempotency_key}}` — a posted journal
      with this key already exists.

  ## Examples

      iex> Logistiki.Accounting.InvariantValidator.validate_idempotency(nil)
      :ok
      iex> Logistiki.Accounting.InvariantValidator.validate_idempotency("evt:1:policy:cash_deposit")
      :ok
  """
  @doc since: "0.1.0"
  @spec validate_idempotency(String.t() | nil) :: :ok | {:error, Error.t()}
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

  @doc """
  Validates that `reversal_postings` exactly negate `original_postings`.

  Checks: same count, same account codes, same amounts, opposite directions,
  same currencies — pairwise in sequence order.

  ## Arguments

    * `original_postings` — `[Posting.t()]` — the original journal's postings.
    * `reversal_postings` — `[Posting.t()]` — the reversal's postings.

  ## Returns

    * `:ok` — the reversal exactly negates the original.
    * `{:error, %Error{code: :unbalanced_journal}}` — the reversal does not
      match.

  ## Examples

      iex> original = [%Posting{account_code: "A", debit_credit: "debit", amount: Decimal.new("100"), currency: "USD", sequence: 1}]
      iex> reversal = [%Posting{account_code: "A", debit_credit: "credit", amount: Decimal.new("100"), currency: "USD", sequence: 1}]
      iex> Logistiki.Accounting.InvariantValidator.validate_reversal(original, reversal)
      :ok
  """
  @doc since: "0.1.0"
  @spec validate_reversal([Posting.t()], [Posting.t()]) :: :ok | {:error, Error.t()}
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

  @doc """
  Validates a journal's full invariant set (postings + accounts + idempotency).

  Combines `validate_postings/1`, `validate_accounts/1`, and
  `validate_idempotency/1` in sequence.

  ## Arguments

    * `journal` — `%Journal{}` — the journal (for the idempotency key).
    * `postings` — `[Posting.t()]` — the journal's postings.

  ## Returns

    * `:ok` — all invariants hold.
    * `{:error, %Error{}}` — the first invariant that failed.

  ## Examples

      iex> Logistiki.Accounting.InvariantValidator.validate(journal, postings)
      :ok
  """
  @doc since: "0.1.0"
  @spec validate(Journal.t(), [Posting.t() | map()]) :: :ok | {:error, Error.t()}
  def validate(%Journal{idempotency_key: key}, postings) do
    with :ok <- validate_postings(postings),
         :ok <- validate_accounts(postings) do
      validate_idempotency(key)
    end
  end

  # ------------------------------------------------------------------
  # Individual invariants
  # ------------------------------------------------------------------

  # Requires at least two postings in the journal.
  defp require_min_two_postings(postings) when length(postings) < 2 do
    {:error,
     Error.new(:unbalanced_journal,
       message: "a journal requires at least two postings",
       stage: :invariant_validation
     )}
  end

  defp require_min_two_postings(_), do: :ok

  # Requires all posting amounts to be positive (> 0).
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

  # Requires all postings to have a non-empty currency string.
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

  # Requires all postings to have a valid debit_credit direction.
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
  # Requires debits to equal credits within each currency group.
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

  # Computes debit and credit totals from a group of postings.
  defp debit_credit_totals(group) do
    Enum.reduce(group, {Decimal.new(0), Decimal.new(0)}, fn p, {debits, credits} ->
      if direction(p) == "debit",
        do: {Decimal.add(debits, amount(p)), credits},
        else: {debits, Decimal.add(credits, amount(p))}
    end)
  end

  # Fetches all accounts by their codes and returns a code-to-account map.
  defp fetch_accounts(codes) when codes == [] do
    {:ok, %{}}
  end

  # Fetches accounts from the DB and returns a code-to-account map. Reports
  # missing accounts as an error.
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

  # Validates a single posting's account: must exist and be a postable leaf.
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

  # Accessors that work for both changesets and structs.
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
