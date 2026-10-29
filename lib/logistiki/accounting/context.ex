defmodule Logistiki.Accounting do
  @moduledoc """
  The context for internal accounting artifacts: journals and postings.

  Applications should normally publish business events (`Logistiki.process/1`)
  rather than calling these functions directly. The functions here are exposed
  for tests, migration, support tools, and controlled administrative
  operations.

  `Logistiki.process/1` commits through `Logistiki.Accounting.Commit`. Direct
  `post_journal/2` remains available for administrative inserts and still uses a
  single Repo transaction for journal+postings with account locks.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Logistiki.Accounting.{Commit, InvariantValidator, Journal, Posting}
  alias Logistiki.Error
  alias Logistiki.Repo
  alias Logistiki.VirtualAccounts

  @doc """
  Fetches a journal by id, raising if not found.
  """
  @doc since: "0.1.0"
  def get_journal!(id), do: Repo.get!(Journal, id) |> Repo.preload(:postings)

  @doc """
  Fetches a journal by id.
  """
  @doc since: "0.1.0"
  def get_journal(id) do
    case Repo.get(Journal, id) do
      nil -> {:error, :not_found}
      journal -> {:ok, Repo.preload(journal, :postings)}
    end
  end

  @doc """
  Lists postings for `journal`, ordered by sequence.
  """
  @doc since: "0.1.0"
  def list_postings(%Journal{id: id}) do
    Repo.all(from(p in Posting, where: p.journal_id == ^id, order_by: [asc: p.sequence]))
  end

  @doc """
  Lists journals, optionally filtered, with postings preloaded.
  """
  @doc since: "0.1.0"
  def list_journals(opts \\ []) do
    Journal
    |> maybe_filter(:status, opts)
    |> maybe_filter(:event_id, opts)
    |> order_by([j], desc: j.inserted_at)
    |> Repo.all()
    |> Repo.preload(:postings)
  end

  defp maybe_filter(query, key, opts) do
    case Keyword.get(opts, key) do
      nil -> query
      value -> where(query, [j], field(j, ^key) == ^value)
    end
  end

  @doc """
  Posts a draft journal and its postings in a single transaction.

  Validates invariants, locks target accounts, inserts journal+postings.
  Prefer `Logistiki.process/1` for application flows that also need durable
  business-event identity and mandatory provenance.
  """
  @doc since: "0.1.0"
  def post_journal(%Journal{status: "draft"} = journal, postings) do
    with :ok <- InvariantValidator.validate(journal, postings) do
      posted_at = DateTime.utc_now(:second)

      Multi.new()
      |> Multi.run(:lock_accounts, fn repo, _ -> lock_accounts(repo, postings) end)
      |> Multi.insert(:journal, fn _ ->
        journal
        |> Map.put(:postings, [])
        |> Journal.changeset(%{status: "posted", posted_at: posted_at})
      end)
      |> Multi.run(:postings, fn repo, %{journal: inserted} ->
        insert_postings(repo, inserted, postings)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{journal: j, postings: posts}} ->
          {:ok, %{j | postings: posts}}

        {:error, _step, reason, _} ->
          {:error, to_error(reason)}

        {:error, reason} ->
          {:error, to_error(reason)}
      end
    end
  end

  def post_journal(%Journal{status: status}, _postings) do
    {:error,
     Error.new(:immutable_journal, message: "only draft journals can be posted, got #{status}")}
  end

  @doc """
  Reverses a posted journal at most once (CAS + unique reversal_of_id).
  """
  @doc since: "0.1.0"
  def reverse_journal(journal, attrs \\ %{})

  def reverse_journal(%Journal{} = journal, attrs) do
    Commit.reverse(journal, attrs)
  end

  @doc """
  Administrative helper to build a draft journal directly from attrs.
  """
  def draft_journal(attrs) do
    %Journal{}
    |> Journal.changeset(attrs)
  end

  defp lock_accounts(repo, postings) do
    codes = Enum.map(postings, & &1.account_code) |> Enum.uniq()

    accounts =
      from(a in VirtualAccounts.VirtualAccount,
        where: a.code in ^codes,
        lock: "FOR UPDATE"
      )
      |> repo.all()

    by_code = Map.new(accounts, &{&1.code, &1})

    Enum.reduce_while(codes, {:ok, by_code}, fn code, {:ok, acc} ->
      check_locked_account(code, by_code, acc)
    end)
  end

  defp check_locked_account(code, by_code, acc) do
    case Map.get(by_code, code) do
      nil ->
        {:halt,
         {:error,
          Error.new(:account_not_found,
            message: "account #{inspect(code)} does not exist",
            details: %{account_code: code},
            stage: :persistence
          )}}

      account ->
        check_postable_account(account, code, acc)
    end
  end

  defp check_postable_account(account, code, acc) do
    if VirtualAccounts.posting_account?(account) do
      {:cont, {:ok, acc}}
    else
      {:halt,
       {:error,
        Error.new(:account_not_postable,
          message: "account #{inspect(code)} is not postable at commit time",
          details: %{account_code: code, status: account.status},
          stage: :persistence
        )}}
    end
  end

  defp insert_postings(repo, journal, postings) do
    account_codes = Enum.map(postings, & &1.account_code) |> Enum.uniq()

    account_by_code =
      from(a in VirtualAccounts.VirtualAccount, where: a.code in ^account_codes)
      |> repo.all()
      |> Map.new(&{&1.code, &1})

    postings
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {p, index}, {:ok, acc} ->
      account = Map.fetch!(account_by_code, p.account_code)
      sequence = if is_integer(p.sequence) and p.sequence > 0, do: p.sequence, else: index
      # Prefer explicit unique sequences; fall back to index when helpers reuse 1.
      sequence =
        if Enum.any?(acc, &(&1.sequence == sequence)), do: index, else: sequence

      cs =
        Posting.changeset(%Posting{}, %{
          journal_id: journal.id,
          virtual_account_id: account.id,
          account_code: p.account_code,
          debit_credit: p.debit_credit,
          amount: p.amount,
          currency: p.currency,
          memo: p.memo,
          sequence: sequence,
          metadata: p.metadata || %{}
        })

      case repo.insert(cs) do
        {:ok, posting} -> {:cont, {:ok, acc ++ [posting]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp to_error(%Error{} = error), do: error

  defp to_error(%Ecto.Changeset{} = cs) do
    cond do
      unique_error?(cs, :idempotency_key) ->
        Error.new(:duplicate_idempotency_key,
          message: "journal idempotency key already exists",
          stage: :persistence
        )

      unique_error?(cs, :reversal_of_id) ->
        Error.new(:duplicate_idempotency_key,
          message: "reversal already exists for journal",
          stage: :persistence
        )

      true ->
        Error.new(:backend_error,
          message: "persistence failed",
          details: %{errors: inspect(cs.errors)},
          stage: :persistence
        )
    end
  end

  defp to_error(reason),
    do: Error.new(:backend_error, message: inspect(reason), stage: :persistence)

  defp unique_error?(%Ecto.Changeset{errors: errors}, field) do
    Enum.any?(errors, fn
      {^field, {_msg, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end
end
