defmodule Logistiki.ProjectionsTest do
  use Logistiki.DataCase, async: false

  alias Logistiki.Demo.Seeds

  setup do
    {entities, accounts} = Seeds.run()
    Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation)
    on_exit(fn -> Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation) end)
    %{entities: entities, accounts: accounts}
  end

  describe "balance projections" do
    test "leaf balance reflects a posting", %{accounts: accounts} do
      assert {:ok, _} = Logistiki.process(Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "500.00"))

      assert {:ok, [cash]} = Logistiki.balance("ASSETS:CASH:USD:NOSTRO")
      assert Decimal.equal?(cash.net, Decimal.new("500.00"))
      assert cash.posting_count == 1
    end

    test "parent balance aggregates descendants", %{accounts: accounts} do
      assert {:ok, _} = Logistiki.process(Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "500.00"))
      assert {:ok, _} = Logistiki.process(Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:PAYROLL", "300.00"))

      assert {:ok, balances} = Logistiki.balance("LIABILITIES:CLIENT_DEPOSITS:USD:ACME")
      net = Enum.reduce(balances, Decimal.new(0), &Decimal.add(&1.net, &2))
      assert Decimal.equal?(net, Decimal.new("-800.00"))
    end

    test "balance_for_entity aggregates linked accounts", %{entities: entities} do
      assert {:ok, _} = Logistiki.process(Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "500.00"))

      assert {:ok, balances} = Logistiki.balance_for_entity(entities.acme_holdings)
      net = Enum.reduce(balances, Decimal.new(0), &Decimal.add(&1.net, &2))
      assert Decimal.equal?(net, Decimal.new("-500.00"))
    end

    test "balance_for_entity_tree aggregates across the entity subtree", %{entities: entities} do
      assert {:ok, _} = Logistiki.process(Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "500.00"))
      assert {:ok, _} = Logistiki.process(Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:BLUEWATER:OPERATING", "200.00"))

      assert {:ok, balances} = Logistiki.balance_for_entity_tree(entities.acme_holdings)
      net = Enum.reduce(balances, Decimal.new(0), &Decimal.add(&1.net, &2))
      # Only Acme-linked accounts; Bluewater is a separate tree.
      assert Decimal.equal?(net, Decimal.new("-500.00"))
    end
  end

  describe "statement projections" do
    test "statement produces ordered running balances", %{accounts: accounts} do
      assert {:ok, _} = Logistiki.process(Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "500.00"))
      assert {:ok, _} = Logistiki.process(Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "250.00"))

      assert {:ok, lines} = Logistiki.statement("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")
      assert length(lines) == 2
      [first, second] = lines
      assert Decimal.equal?(first.running_balance, Decimal.new("-500.00"))
      assert Decimal.equal?(second.running_balance, Decimal.new("-750.00"))
      assert first.selected_policy == "cash_deposit"
    end
  end

  describe "trial balance" do
    test "trial balance balances per currency", %{accounts: accounts} do
      assert {:ok, _} = Logistiki.process(Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "500.00"))
      assert {:ok, _} = Logistiki.process(Seeds.fee_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "25.00"))

      assert {:ok, tb} = Logistiki.trial_balance()
      assert "USD" in tb.currencies
      assert tb.balanced
    end
  end

  describe "balance sheet and income statement" do
    test "balance sheet separates assets, liabilities, equity", %{accounts: accounts} do
      assert {:ok, _} = Logistiki.process(Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "500.00"))

      bs = Logistiki.balance_sheet()
      assert length(bs.assets.balances) == 1
      assert length(bs.liabilities.balances) == 1
      assert Decimal.equal?(bs.totals_by_currency["USD"][:assets], Decimal.new("500.00"))
      assert Decimal.equal?(bs.totals_by_currency["USD"][:liabilities], Decimal.new("-500.00"))
    end

    test "income statement separates income and expenses with net profit", %{accounts: accounts} do
      assert {:ok, _} = Logistiki.process(Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "1000.00"))
      assert {:ok, _} = Logistiki.process(Seeds.fee_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "25.00"))

      is = Logistiki.income_statement()
      assert length(is.income.balances) == 1
      # Fee income: credit 25 => net (debit - credit) = -25.
      assert Decimal.equal?(is.net_profit_by_currency["USD"], Decimal.new("-25.00"))
    end
  end

  describe "general ledger" do
    test "general ledger lists all postings" do
      assert {:ok, _} = Logistiki.process(Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "500.00"))

      gl = Logistiki.general_ledger()
      assert length(gl.lines) == 2
    end
  end
end
