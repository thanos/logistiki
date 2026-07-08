defmodule Logistiki.Projections.MiscTest do
  use Logistiki.DataCase, async: false

  alias Logistiki.Demo.Seeds
  alias Logistiki.Projections

  setup do
    {entities, accounts} = Seeds.run()
    Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation)
    on_exit(fn -> Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation) end)
    {:ok, entities: entities, accounts: accounts}
  end

  describe "balance_for_entity/2" do
    test "returns balances for entity-linked accounts", %{entities: entities} do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "500.00")
      {:ok, _} = Logistiki.process(event)
      {:ok, balances} = Projections.balance_for_entity(entities.acme_holdings)
      assert is_list(balances)
    end
  end

  describe "balance_for_entity_tree/2" do
    test "returns balances for entity subtree", %{entities: entities} do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "500.00")
      {:ok, _} = Logistiki.process(event)
      {:ok, balances} = Projections.balance_for_entity_tree(entities.acme_holdings)
      assert is_list(balances)
    end
  end

  describe "general_ledger/1" do
    test "returns a GeneralLedger struct with lines" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, _} = Logistiki.process(event)
      gl = Projections.general_ledger()
      assert %Logistiki.Projections.GeneralLedger{} = gl
      assert length(gl.lines) >= 2
    end
  end

  describe "balance_sheet/1" do
    test "returns a BalanceSheet struct" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, _} = Logistiki.process(event)
      bs = Projections.balance_sheet()
      assert %Logistiki.Projections.BalanceSheet{} = bs
    end
  end

  describe "income_statement/1" do
    test "returns an IncomeStatement struct" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "1000.00")
      {:ok, _} = Logistiki.process(event)
      fee = Seeds.fee_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "25.00")
      {:ok, _} = Logistiki.process(fee)
      is = Projections.income_statement()
      assert %Logistiki.Projections.IncomeStatement{} = is
    end
  end

  describe "balance/2" do
    test "delegates to ProjectionEngine" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, _} = Logistiki.process(event)
      {:ok, balances} = Projections.balance("ASSETS:CASH:USD:NOSTRO")
      assert is_list(balances)
    end
  end

  describe "statement/2" do
    test "delegates to ProjectionEngine" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, _} = Logistiki.process(event)
      {:ok, lines} = Projections.statement("ASSETS:CASH:USD:NOSTRO")
      assert is_list(lines)
    end
  end

  describe "trial_balance/1" do
    test "delegates to ProjectionEngine" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, _} = Logistiki.process(event)
      tb = Projections.trial_balance()
      assert %Logistiki.Projections.TrialBalance{} = tb
    end
  end
end
