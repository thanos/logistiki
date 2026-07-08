defmodule Logistiki.Ledger.Simulation do
  @moduledoc """
  The simulation ledger backend.

  It is fast, deterministic, and has no external dependencies. It uses
  Logistiki's own persisted journal/posting tables (via
  `Logistiki.Accounting` and `Logistiki.Projections.ProjectionEngine`) to
  execute journals and compute balances and statements.

  This is the baseline behavior that the Beancount oracle backend must match.
  """

  @behaviour Logistiki.Ledger.Behaviour

  alias Logistiki.Accounting
  alias Logistiki.Ledger.Result
  alias Logistiki.Projections.ProjectionEngine

  @impl true
  def execute_journal(journal, opts \\ []) do
    postings = journal.postings || []

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
           details: %{journal: posted}
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  def reverse_journal(journal, attrs, opts \\ []) do
    case Accounting.reverse_journal(journal, attrs) do
      {:ok, reversal} ->
        balances = compute_affected_balances(reversal, opts)

        {:ok,
         %Result{
           backend: __MODULE__,
           journal_id: reversal.id,
           status: :ok,
           posted_at: reversal.posted_at,
           balances: balances,
           details: %{reversal: reversal}
         }}

      {:error, error} ->
        {:error, error}
    end
  end

  @impl true
  def balance(account, opts \\ []) do
    case ProjectionEngine.balance(account, opts) do
      {:ok, balances} -> {:ok, balances}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def statement(account, opts \\ []) do
    ProjectionEngine.statement(account, opts)
  end

  @impl true
  def trial_balance(opts \\ []) do
    {:ok, ProjectionEngine.trial_balance(opts)}
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
