defmodule Logistiki.Accounting do
  @moduledoc """
  The context for internal accounting artifacts: journals and postings.

  Applications should normally publish business events (`Logistiki.process/1`)
  rather than calling these functions directly. The functions here are exposed
  for tests, migration, support tools, and controlled administrative
  operations.
  """

  import Ecto.Query

  alias Logistiki.Accounting.{InvariantValidator, Journal, JournalBuilder, Posting}
  alias Logistiki.Error
  alias Logistiki.Repo
  alias Logistiki.VirtualAccounts

  @doc """
  Fetches a journal by id, raising if not found.

  ## Arguments

    * `id` — `integer()` — the journal primary key.

  ## Returns

    * `%Journal{}` — the journal with postings preloaded. Raises
      `Ecto.NoResultsError` if not found.

  ## Examples

      iex> journal = Logistiki.Accounting.get_journal!(1)
      iex> journal.status
      "posted"
      iex> journal.postings
      [%Posting{...}, %Posting{...}]
  """
  @doc since: "0.1.0"
  def get_journal!(id), do: Repo.get!(Journal, id) |> Repo.preload(:postings)

  @doc """
  Fetches a journal by id.

  ## Arguments

    * `id` — `integer()` — the journal primary key.

  ## Returns

    * `{:ok, %Journal{}}` — the journal with postings preloaded.
    * `{:error, :not_found}` — no journal with that id.

  ## Examples

      iex> {:ok, journal} = Logistiki.Accounting.get_journal(1)
      iex> journal.status
      "posted"
      iex> {:error, :not_found} = Logistiki.Accounting.get_journal(999)
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

  ## Arguments

    * `journal` — `%Journal{}` — the journal whose postings to list.

  ## Returns

    * `[Posting.t()]` — ordered by `sequence` ascending.

  ## Examples

      iex> Logistiki.Accounting.list_postings(journal)
      [%Posting{sequence: 1, ...}, %Posting{sequence: 2, ...}]
  """
  @doc since: "0.1.0"
  def list_postings(%Journal{id: id}) do
    Repo.all(from(p in Posting, where: p.journal_id == ^id, order_by: [asc: p.sequence]))
  end

  @doc """
  Lists journals, optionally filtered, with postings preloaded.

  ## Arguments

    * `opts` — `keyword()` of options:
        * `:status` — `String.t` — e.g. `"posted"`, `"draft"`, `"reversed"`
        * `:event_id` — `String.t` — filter by originating event id

  ## Returns

    * `[Journal.t()]` — ordered by `inserted_at` descending, with `:postings`
      preloaded. Empty list if none match.

  ## Examples

      iex> Logistiki.Accounting.list_journals(status: "posted")
      [%Journal{status: "posted", postings: [%Posting{...}, ...]}, ...]

      iex> Logistiki.Accounting.list_journals(event_id: "evt_001")
      [%Journal{event_id: "evt_001", ...}]
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

  # maybe_filter — private helper.
  defp maybe_filter(query, key, opts) do
    case Keyword.get(opts, key) do
      nil -> query
      value -> where(query, [j], field(j, ^key) == ^value)
    end
  end

  @doc """
  Posts a draft journal and its postings.

  Validates the full invariant set, resolves `virtual_account_id` for each
  posting from its `account_code`, then inserts the journal (status `posted`)
  and its postings in a single transaction.

  Returns `{:ok, posted_journal}` or `{:error, %Logistiki.Error{}}`.
  """
  @doc since: "0.1.0"
  def post_journal(%Journal{status: "draft"} = journal, postings) do
    with :ok <- InvariantValidator.validate(journal, postings) do
      Repo.transaction(fn ->
        posted_at = DateTime.utc_now(:second)

        # Strip the in-memory postings so Repo.insert does not also insert them
        # (they are inserted explicitly below with resolved account ids).
        {:ok, inserted_journal} =
          journal
          |> Map.put(:postings, [])
          |> Journal.changeset(%{status: "posted", posted_at: posted_at})
          |> Repo.insert()

        {:ok, inserted_postings} = insert_postings(inserted_journal, postings)

        %{inserted_journal | postings: inserted_postings}
      end)
      |> normalize_transaction_result()
    end
  end

  def post_journal(%Journal{status: status}, _postings) do
    {:error,
     Error.new(:immutable_journal, message: "only draft journals can be posted, got #{status}")}
  end

  @doc """
  Reverses a posted journal by creating a new posted reversal journal that
  exactly negates the original postings, and marks the original `reversed`.

  Returns `{:ok, reversal_journal}` or `{:error, %Logistiki.Error{}}`.
  """
  def reverse_journal(journal, attrs \\ %{})

  def reverse_journal(%Journal{status: "posted"} = journal, attrs) do
    postings = list_postings(journal)
    {:ok, reversal, reversal_postings} = JournalBuilder.build_reversal(journal, postings, attrs)

    with :ok <- InvariantValidator.validate_reversal(postings, reversal_postings) do
      Repo.transaction(fn ->
        posted_at = DateTime.utc_now(:second)

        {:ok, inserted_reversal} =
          reversal
          |> Map.put(:postings, [])
          |> Journal.changeset(%{status: "posted", posted_at: posted_at})
          |> Repo.insert()

        {:ok, inserted_postings} = insert_postings(inserted_reversal, reversal_postings)

        # Mark the original journal as reversed.
        {1, _} =
          Repo.update_all(
            from(j in Journal, where: j.id == ^journal.id),
            set: [status: "reversed", reversed_at: posted_at]
          )

        %{inserted_reversal | postings: inserted_postings}
      end)
      |> normalize_transaction_result()
    end
  end

  def reverse_journal(%Journal{status: status}, _attrs) do
    {:error,
     Error.new(:immutable_journal, message: "only posted journals can be reversed, got #{status}")}
  end

  @doc """
  Administrative helper to build a draft journal directly from attrs (for tests,
  migration, and support tools). Not the normal application-facing API.
  """
  def draft_journal(attrs) do
    %Journal{}
    |> Journal.changeset(attrs)
  end

  # insert_postings — private helper.
  defp insert_postings(journal, postings) do
    account_codes = Enum.map(postings, & &1.account_code) |> Enum.uniq()
    account_by_code = accounts_by_code(account_codes)

    inserted =
      Enum.map(postings, fn p ->
        account = Map.fetch!(account_by_code, p.account_code)

        {:ok, posting} =
          Posting.changeset(%Posting{}, %{
            journal_id: journal.id,
            virtual_account_id: account.id,
            account_code: p.account_code,
            debit_credit: p.debit_credit,
            amount: p.amount,
            currency: p.currency,
            memo: p.memo,
            sequence: p.sequence,
            metadata: p.metadata
          })
          |> Repo.insert()

        posting
      end)

    {:ok, inserted}
  end

  # accounts_by_code — private helper.
  defp accounts_by_code(codes) do
    VirtualAccounts.list_accounts()
    |> Enum.into(%{}, fn a -> {a.code, a} end)
    |> Map.take(codes)
  end

  # normalize_transaction_result — private helper.
  defp normalize_transaction_result({:ok, result}), do: {:ok, result}
  defp normalize_transaction_result({:error, reason}), do: {:error, to_error(reason)}

  # to_error — private helper.
  defp to_error(%Error{} = error), do: error

  defp to_error(%Ecto.Changeset{} = cs),
    do:
      Error.new(:backend_error,
        message: "persistence failed",
        details: inspect(cs),
        stage: :persistence
      )

  defp to_error(reason),
    do: Error.new(:backend_error, message: inspect(reason), stage: :persistence)
end
