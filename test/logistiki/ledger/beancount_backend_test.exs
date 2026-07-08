defmodule Logistiki.Ledger.BeancountTest do
  use Logistiki.DataCase, async: false

  alias Logistiki.Demo.Seeds
  alias Logistiki.Ledger.Beancount

  setup do
    Seeds.run()
    Logistiki.put_ledger_backend(Beancount)
    on_exit(fn -> Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation) end)
    :ok
  end

  describe "execute_journal/2" do
    test "executes a deposit through the oracle" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "1000.00")
      {:ok, result} = Logistiki.process(event)
      assert result.ledger_result.backend == Beancount
      assert result.ledger_result.details[:oracle] == :beancount
    end
  end

  describe "reverse_journal/3" do
    test "reverses a journal through the oracle" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "500.00")
      {:ok, result} = Logistiki.process(event)
      {:ok, reversal} = Beancount.reverse_journal(result.journal, %{reason: "test"})
      assert reversal.status == :ok
    end
  end

  describe "verify_ledger/1" do
    test "verifies the full ledger with Beancount.check" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "200.00")
      {:ok, _} = Logistiki.process(event)
      assert {:ok, _} = Beancount.verify_ledger()
    end
  end

  describe "oracle_balances/1" do
    test "returns oracle balances as a map" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "300.00")
      {:ok, _} = Logistiki.process(event)
      assert {:ok, balances} = Beancount.oracle_balances()
      assert is_map(balances)
    end
  end
end
