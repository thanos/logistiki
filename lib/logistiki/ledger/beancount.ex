defmodule Logistiki.Ledger.Beancount do
  @moduledoc """
  The Beancount ledger backend — the accounting oracle.

  Uses `beancount_ex` as the executable accounting specification. On
  `execute_journal/2` the journal is mapped to Beancount directives and verified
  with `Beancount.check/1` before being persisted. Projections (`balance`,
  `statement`, `trial_balance`) are computed from Logistiki's own persisted
  postings via `Logistiki.Projections.ProjectionEngine`, so the simulation and
  Beancount backends agree by construction. The oracle value of Beancount is
  exercised by `verify_ledger/1` and the regression test suite, which compare
  Beancount-derived balances against Logistiki's.

  Beancount-specific structs do not leak into the public API.
  """

  @behaviour Logistiki.Ledger.Behaviour

  import Ecto.Query

  alias Logistiki.Accounting
  alias Logistiki.Accounting.Journal
  alias Logistiki.Ledger.BeancountMapper
  alias Logistiki.Ledger.Result
  alias Logistiki.Projections.ProjectionEngine
  alias Logistiki.Repo
  alias Logistiki.VirtualAccounts.VirtualAccount

  @impl true
  def execute_journal(journal, opts \\ []) do
    postings = journal.postings || []

    with :ok <- verify_with_oracle(journal, postings) do
      case Accounting.post_journal(journal, postings) do
        {:ok, posted} ->
          balances = compute_affected_balances(posted, opts)

          {:ok,
           %Result{
             backend: __MODULE__,
             journal_id: posted.id,
             status: :ok,
             posted_at: posted.posted_at,
             balances: balances,
             details: %{journal: posted, oracle: :beancount}
           }}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @impl true
  def reverse_journal(journal, attrs, opts \\ []) do
    with {:ok, reversal} <- build_and_verify_reversal(journal, attrs) do
      balances = compute_affected_balances(reversal, opts)

      {:ok,
       %Result{
         backend: __MODULE__,
         journal_id: reversal.id,
         status: :ok,
         posted_at: reversal.posted_at,
         balances: balances,
         details: %{reversal: reversal, oracle: :beancount}
       }}
    end
  end

  @impl true
  def balance(account, opts \\ []) do
    ProjectionEngine.balance(account, opts)
  end

  @impl true
  def statement(account, opts \\ []) do
    ProjectionEngine.statement(account, opts)
  end

  @impl true
  def trial_balance(opts \\ []) do
    {:ok, ProjectionEngine.trial_balance(opts)}
  end

  @doc """
  Renders all posted journals to a Beancount ledger and verifies it with
  `Beancount.check/1`. Used by the regression suite to exercise the oracle.
  """
  @doc since: "0.1.0"
  def verify_ledger(opts \\ []) do
    _ = opts

    journals =
      from(j in Journal,
        where: j.status in ["posted", "reversed"],
        order_by: [asc: j.effective_date, asc: j.inserted_at],
        preload: [:postings]
      )
      |> Repo.all()

    account_codes =
      journals
      |> Enum.flat_map(fn j -> Enum.map(j.postings, & &1.account_code) end)
      |> Enum.uniq()

    accounts = accounts_by_code(account_codes)
    account_values = Map.values(accounts)

    directives =
      BeancountMapper.to_beancount_opens(account_values) ++
        Enum.map(journals, &BeancountMapper.to_beancount_directive(&1, &1.postings, accounts))

    ledger_text = Beancount.render(directives)
    Beancount.check_text(ledger_text)
  end

  @doc "Returns Beancount balances for all posted journals (oracle projection)."
  @doc since: "0.1.0"
  def oracle_balances(opts \\ []) do
    currency = Keyword.get(opts, :currency)

    journals =
      from(j in Journal,
        where: j.status in ["posted", "reversed"],
        order_by: [asc: j.effective_date, asc: j.inserted_at],
        preload: [:postings]
      )
      |> Repo.all()

    account_codes =
      journals
      |> Enum.flat_map(fn j -> Enum.map(j.postings, & &1.account_code) end)
      |> Enum.uniq()

    accounts = accounts_by_code(account_codes)
    account_values = Map.values(accounts)

    directives =
      BeancountMapper.to_beancount_opens(account_values) ++
        Enum.map(journals, &BeancountMapper.to_beancount_directive(&1, &1.postings, accounts))

    bql =
      if currency do
        "SELECT account, sum(position) AS balance WHERE currency = '#{currency}' GROUP BY account ORDER BY account"
      else
        "SELECT account, sum(position) AS balance GROUP BY account ORDER BY account"
      end

    case Beancount.query(directives, bql) do
      {:ok, result} -> {:ok, BeancountMapper.from_beancount_balance(result)}
      {:error, _} = err -> err
    end
  end

  # verify_with_oracle — private helper.
  defp verify_with_oracle(journal, postings) do
    account_codes = Enum.map(postings, & &1.account_code) |> Enum.uniq()
    accounts = accounts_by_code(account_codes)

    if Enum.all?(account_codes, &Map.has_key?(accounts, &1)) do
      opens = BeancountMapper.to_beancount_opens(Map.values(accounts))
      txn = BeancountMapper.to_beancount_directive(journal, postings, accounts)
      ledger_text = Beancount.render(opens ++ [txn])

      case Beancount.check_text(ledger_text) do
        {:ok, _} -> :ok
        {:error, result} -> {:error, oracle_error(result)}
      end
    else
      {:error,
       Logistiki.Error.new(:account_not_found,
         message: "beancount backend could not resolve all accounts",
         stage: :ledger_backend
       )}
    end
  end

  # build_and_verify_reversal — private helper.
  defp build_and_verify_reversal(journal, attrs) do
    with :ok <- verify_reversal_with_oracle(journal, attrs) do
      Accounting.reverse_journal(journal, attrs)
    end
  end

  # verify_reversal_with_oracle — private helper.
  defp verify_reversal_with_oracle(journal, attrs) do
    postings = Accounting.list_postings(journal)
    {:ok, reversal, reversal_postings} = Logistiki.Accounting.JournalBuilder.build_reversal(journal, postings, attrs)
    verify_with_oracle(reversal, reversal_postings)
  end

  # oracle_error — private helper.
  defp oracle_error(%Beancount.Result{stderr: stderr, normalized: normalized}) do
    Logistiki.Error.new(:backend_error,
      message: "beancount oracle rejected the journal: #{stderr}#{inspect(normalized)}",
      stage: :ledger_backend
    )
  end

  # oracle_error — private helper.
  defp oracle_error(reason) do
    Logistiki.Error.new(:backend_error,
      message: "beancount oracle error: #{inspect(reason)}",
      stage: :ledger_backend
    )
  end

  # accounts_by_code — private helper.
  defp accounts_by_code(codes) when codes == [] do
    %{}
  end

  # accounts_by_code — private helper.
  defp accounts_by_code(codes) do
    Repo.all(from a in VirtualAccount, where: a.code in ^codes)
    |> Enum.into(%{}, fn a -> {a.code, a} end)
  end

  # compute_affected_balances — private helper.
  defp compute_affected_balances(journal, opts) do
    postings = journal.postings || []

    postings
    |> Enum.map(& &1.account_code)
    |> Enum.uniq()
    |> Enum.into(%{}, fn code ->
      case ProjectionEngine.balance(code, opts) do
        {:ok, balances} -> {code, balances}
        {:error, _} -> {code, []}
      end
    end)
  end
end
