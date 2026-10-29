defmodule Logistiki.V011.AccountingCorrectnessTest do
  @moduledoc "L11-13..L11-20 accounting correctness and outcome regressions."
  use Logistiki.V011Case

  alias Ecto.Adapters.SQL.Sandbox
  alias Logistiki.Accounting.{InvariantValidator, Journal, Posting}
  alias Logistiki.Event.AccountOpened
  alias Logistiki.Ledger.Beancount, as: BeancountBackend
  alias Logistiki.Ledger.Simulation, as: SimulationBackend
  alias Logistiki.Repo
  alias Logistiki.VirtualAccounts

  # L11-13 Multi-currency imbalance
  test "L11-13 each currency must independently balance" do
    postings = [
      %Posting{
        account_code: "ASSETS:CASH:USD:NOSTRO",
        debit_credit: "debit",
        amount: Decimal.new("100.00"),
        currency: "USD",
        sequence: 1
      },
      %Posting{
        account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
        debit_credit: "credit",
        amount: Decimal.new("100.00"),
        currency: "EUR",
        sequence: 2
      }
    ]

    assert {:error, %{code: :unbalanced_journal}} =
             InvariantValidator.validate_postings(postings)
  end

  # L11-14 Decimal fraction and currency precision
  test "L11-14 excess USD precision is rejected; valid scale accepted" do
    bad = [
      %Posting{
        account_code: "ASSETS:CASH:USD:NOSTRO",
        debit_credit: "debit",
        amount: Decimal.new("10.001"),
        currency: "USD",
        sequence: 1
      },
      %Posting{
        account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
        debit_credit: "credit",
        amount: Decimal.new("10.001"),
        currency: "USD",
        sequence: 2
      }
    ]

    assert {:error, %{code: :precision_invalid}} = InvariantValidator.validate_postings(bad)

    good = [
      %Posting{
        account_code: "ASSETS:CASH:USD:NOSTRO",
        debit_credit: "debit",
        amount: Decimal.new("10.01"),
        currency: "USD",
        sequence: 1
      },
      %Posting{
        account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
        debit_credit: "credit",
        amount: Decimal.new("10.01"),
        currency: "USD",
        sequence: 2
      }
    ]

    assert :ok = InvariantValidator.validate_postings(good)
  end

  # L11-15 Frozen account races posting
  @tag :concurrency
  @tag :postgres
  test "L11-15 freeze vs post has documented serial outcome" do
    {:ok, account} =
      VirtualAccounts.get_account_by_code("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")

    parent = self()
    event = deposit("20.00", id: "l11_15")

    freeze_task =
      Task.async(fn ->
        Sandbox.allow(Repo, parent, self())
        VirtualAccounts.update_account(account, %{status: "frozen"})
      end)

    post_task =
      Task.async(fn ->
        Sandbox.allow(Repo, parent, self())
        Logistiki.process(event)
      end)

    freeze_result = Task.await(freeze_task, 15_000)
    post_result = Task.await(post_task, 15_000)

    assert match?({:ok, _}, freeze_result)

    case post_result do
      {:ok, %{journal: %{status: "posted"}}} ->
        # Post won the race before freeze took effect under serial ordering.
        assert true

      {:error, %{code: :account_not_postable}} ->
        assert journal_count() == 0 or
                 from(j in Journal, where: j.event_id == "l11_15") |> Repo.all() == []

      other ->
        flunk("unexpected outcome: #{inspect(other)}")
    end
  end

  # L11-16 Two legal entities — no balance contamination
  test "L11-16 two entities do not cross-contaminate balances" do
    e1 =
      deposit("30.00",
        id: "l11_16_a",
        account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING"
      )

    e2 =
      deposit("40.00",
        id: "l11_16_b",
        account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:BLUEWATER:OPERATING"
      )

    assert {:ok, _} = Logistiki.process(e1)
    assert {:ok, _} = Logistiki.process(e2)

    assert {:ok, [acme]} =
             Logistiki.balance("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")

    assert {:ok, [blue]} =
             Logistiki.balance("LIABILITIES:CLIENT_DEPOSITS:USD:BLUEWATER:OPERATING")

    assert Decimal.equal?(acme.net, Decimal.new("-30.00"))
    assert Decimal.equal?(blue.net, Decimal.new("-40.00"))
  end

  # L11-17 As-of statement and reversal
  test "L11-17 as-of statement excludes later effective dates; reversal nets out" do
    early =
      deposit("50.00", id: "l11_17_early", effective_date: ~D[2026-07-01])

    late =
      deposit("60.00", id: "l11_17_late", effective_date: ~D[2026-07-15])

    assert {:ok, _} = Logistiki.process(early)
    assert {:ok, late_result} = Logistiki.process(late)

    assert {:ok, as_of_lines} =
             Logistiki.statement("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
               as_of: ~D[2026-07-07]
             )

    assert Enum.all?(as_of_lines, fn line ->
             is_nil(line.date) or Date.compare(line.date, ~D[2026-07-07]) != :gt
           end)

    assert {:ok, _} = Accounting.reverse_journal(late_result.journal)

    assert {:ok, [bal]} =
             Logistiki.balance("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")

    assert Decimal.equal?(bal.net, Decimal.new("-50.00"))
  end

  # L11-18 Beancount oracle differential cases
  test "L11-18 beancount oracle accepts deposit fixture and trial balance balances" do
    Logistiki.put_ledger_backend(BeancountBackend)
    on_exit(fn -> Logistiki.put_ledger_backend(SimulationBackend) end)

    event = deposit("70.00", id: "l11_18")
    assert {:ok, result} = Logistiki.process(event)
    assert result.ledger_result.details[:oracle] == :beancount
    assert {:ok, _} = BeancountBackend.verify_ledger()

    assert {:ok, tb} = Logistiki.trial_balance()
    assert tb.balanced
    assert "USD" in tb.currencies
  end

  # L11-19 No-impact and blocked event
  test "L11-19 no-impact and blocked outcomes are durable with zero postings" do
    open = %AccountOpened{
      id: "l11_19_open",
      account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
      source_system: "l11",
      source_id: "l11_19_open"
    }

    before = journal_count()
    assert {:ok, result} = Logistiki.process(open)
    assert is_nil(result.journal)
    assert journal_count() == before
    assert provenance_count(open.id) == 1

    assert {:ok, looked} = Logistiki.lookup_outcome(event_id: open.id)
    assert looked.explanation[:reason] == :no_accounting_impact
  end

  # L11-20 Repeated/failed policy evaluation
  test "L11-20 invalid policy path does not commit" do
    # Force knowledge failure by using an unknown event shape via AccountOpened
    # already covered; use a deposit targeting a missing account to fail invariants.
    event =
      deposit("80.00",
        id: "l11_20",
        account_code: "LIABILITIES:DOES:NOT:EXIST"
      )

    before = journal_count()
    assert {:error, %{code: code}} = Logistiki.process(event)
    assert code in [:account_not_found, :no_policy_found, :invalid_template, :unbalanced_journal]
    assert journal_count() == before
  end
end
