defmodule Logistiki.V011Case do
  @moduledoc """
  Shared setup for v0.1.1 durability regression tests (L11-*).

  Concurrency-tagged tests use a shared sandbox owner so spawned tasks can
  participate in the same transaction visibility (PostgreSQL required).
  """

  use ExUnit.CaseTemplate

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Logistiki.Accounting.{Journal, Posting}
  alias Logistiki.Audit.AuditEvent
  alias Logistiki.Demo.Seeds
  alias Logistiki.Event.DepositReceived
  alias Logistiki.Repo

  using do
    quote do
      use ExUnit.Case, async: false

      import Ecto.Query
      import Logistiki.V011Case

      alias Logistiki.Accounting
      alias Logistiki.Accounting.{Journal, Posting}
      alias Logistiki.Audit
      alias Logistiki.Demo.Seeds
      alias Logistiki.Event.DepositReceived
      alias Logistiki.Events
      alias Logistiki.Events.BusinessEvent
      alias Logistiki.Repo
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(pid) end)

    Seeds.run()

    Application.delete_env(:logistiki, :inject_commit_failure)

    _ = tags[:concurrency]

    :ok
  end

  @doc "Builds a unique USD deposit event."
  def deposit(amount \\ "100.00", opts \\ []) do
    id = opts[:id] || "l11_dep_#{System.unique_integer([:positive])}"
    source_system = opts[:source_system] || "l11"
    source_id = opts[:source_id] || id

    %DepositReceived{
      id: id,
      entity_type: "corporate",
      account_code: opts[:account_code] || "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
      cash_account_code: opts[:cash_account_code] || "ASSETS:CASH:USD:NOSTRO",
      amount: Decimal.new(amount),
      currency: opts[:currency] || "USD",
      occurred_at: ~U[2026-07-07 12:00:00Z],
      effective_date: opts[:effective_date] || ~D[2026-07-07],
      source_system: source_system,
      source_id: source_id
    }
  end

  @doc "Counts posted journals in the database."
  def posted_journal_count do
    Repo.aggregate(from(j in Journal, where: j.status == "posted"), :count, :id)
  end

  @doc "Counts all journals."
  def journal_count do
    Repo.aggregate(Journal, :count, :id)
  end

  @doc "Counts postings."
  def posting_count do
    Repo.aggregate(Posting, :count, :id)
  end

  @doc "Counts commit_provenance audit rows for an event id."
  def provenance_count(event_id) do
    Repo.aggregate(
      from(a in AuditEvent,
        where: a.event_id == ^to_string(event_id) and a.action == "commit_provenance"
      ),
      :count,
      :id
    )
  end
end
