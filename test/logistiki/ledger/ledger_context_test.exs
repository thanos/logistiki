defmodule Logistiki.LedgerContextTest do
  use Logistiki.DataCase, async: false

  alias Logistiki.Demo.Seeds
  alias Logistiki.Ledger

  setup do
    {entities, accounts} = Seeds.run()
    Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation)
    on_exit(fn -> Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation) end)
    %{entities: entities, accounts: accounts}
  end

  describe "backend/0" do
    test "returns the configured backend" do
      assert Ledger.backend() == Logistiki.Ledger.Simulation
    end
  end

  describe "put_backend/1" do
    test "sets the backend at runtime" do
      Ledger.put_backend(Logistiki.Ledger.Beancount)
      assert Ledger.backend() == Logistiki.Ledger.Beancount
      Ledger.put_backend(Logistiki.Ledger.Simulation)
    end
  end

  describe "backends/0" do
    test "returns available backends" do
      backends = Ledger.backends()
      assert Logistiki.Ledger.Simulation in backends
      assert Logistiki.Ledger.Beancount in backends
    end
  end

  describe "execute_journal/2" do
    test "executes a journal through the configured backend" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, result} = Logistiki.process(event)
      assert result.ledger_result.status == :ok
    end
  end

  describe "reverse_journal/3" do
    test "reverses a journal through the configured backend" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, result} = Logistiki.process(event)
      {:ok, reversal} = Ledger.reverse_journal(result.journal, %{reason: "test"})
      assert reversal.status == :ok
    end
  end

  describe "balance/2" do
    test "computes balance through the backend" do
      {:ok, balances} = Ledger.balance("ASSETS:CASH:USD:NOSTRO")
      assert is_list(balances)
    end
  end

  describe "statement/2" do
    test "computes statement through the backend" do
      {:ok, lines} = Ledger.statement("ASSETS:CASH:USD:NOSTRO")
      assert is_list(lines)
    end
  end

  describe "trial_balance/1" do
    test "computes trial balance through the backend" do
      {:ok, tb} = Ledger.trial_balance()
      assert %Logistiki.Projections.TrialBalance{} = tb
    end
  end
end
