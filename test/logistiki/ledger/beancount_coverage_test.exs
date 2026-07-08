defmodule Logistiki.Ledger.BeancountCoverageTest do
  use Logistiki.DataCase, async: false

  alias Logistiki.Accounting
  alias Logistiki.Demo.Seeds
  alias Logistiki.Ledger.Beancount

  setup do
    Seeds.run()
    Logistiki.put_ledger_backend(Beancount)
    on_exit(fn -> Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation) end)
    :ok
  end

  describe "execute_journal/2 error paths" do
    test "returns error when account not found" do
      alias Logistiki.Accounting.{Journal, Posting}

      journal = %Journal{
        status: "draft",
        effective_date: ~D[2026-07-07],
        idempotency_key: "test_nonexistent_#{:rand.uniform(1_000_000)}",
        selected_policy: "cash_deposit",
        description: "test"
      }

      postings = [
        %Posting{
          account_code: "NONEXISTENT:CODE",
          debit_credit: "debit",
          amount: Decimal.new("100"),
          currency: "USD",
          sequence: 1
        },
        %Posting{
          account_code: "ALSO:NONEXISTENT",
          debit_credit: "credit",
          amount: Decimal.new("100"),
          currency: "USD",
          sequence: 2
        }
      ]

      journal_with_postings = %{journal | postings: postings}

      assert {:error, %{code: :account_not_found}} =
               Beancount.execute_journal(journal_with_postings)
    end
  end

  describe "reverse_journal/3" do
    test "reverses a posted journal through the oracle" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "200.00")
      {:ok, result} = Logistiki.process(event)
      {:ok, reversal} = Beancount.reverse_journal(result.journal, %{reason: "test"})
      assert reversal.status == :ok
      assert reversal.details[:oracle] == :beancount
    end
  end

  describe "verify_ledger/1" do
    test "verifies after processing multiple events" do
      event1 = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, _} = Logistiki.process(event1)

      event2 = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:PAYROLL", "200.00")
      {:ok, _} = Logistiki.process(event2)

      assert {:ok, _} = Beancount.verify_ledger()
    end
  end

  describe "oracle_balances/1" do
    test "returns balances for all currencies" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "300.00")
      {:ok, _} = Logistiki.process(event)

      assert {:ok, _} = Beancount.oracle_balances()
    end
  end

  describe "balance/2" do
    test "delegates to ProjectionEngine" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "50.00")
      {:ok, _} = Logistiki.process(event)
      {:ok, balances} = Beancount.balance("ASSETS:CASH:USD:NOSTRO")
      assert is_list(balances)
    end
  end

  describe "statement/2" do
    test "delegates to ProjectionEngine" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "50.00")
      {:ok, _} = Logistiki.process(event)
      {:ok, lines} = Beancount.statement("ASSETS:CASH:USD:NOSTRO")
      assert is_list(lines)
    end
  end

  describe "trial_balance/1" do
    test "delegates to ProjectionEngine" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "50.00")
      {:ok, _} = Logistiki.process(event)
      {:ok, tb} = Beancount.trial_balance()
      assert %Logistiki.Projections.TrialBalance{} = tb
    end
  end
end
