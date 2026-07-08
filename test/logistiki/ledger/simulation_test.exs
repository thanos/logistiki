defmodule Logistiki.Ledger.SimulationTest do
  use Logistiki.DataCase, async: false

  alias Logistiki.Demo.Seeds
  alias Logistiki.Ledger.Simulation

  setup do
    {entities, accounts} = Seeds.run()
    Logistiki.put_ledger_backend(Simulation)
    %{entities: entities, accounts: accounts}
  end

  describe "balance/2" do
    test "computes balance directly" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, _} = Logistiki.process(event)
      {:ok, [balance]} = Simulation.balance("ASSETS:CASH:USD:NOSTRO")
      assert Decimal.equal?(balance.net, Decimal.new("100"))
    end
  end

  describe "statement/2" do
    test "computes statement directly" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, _} = Logistiki.process(event)
      {:ok, lines} = Simulation.statement("ASSETS:CASH:USD:NOSTRO")
      assert Enum.empty?(lines) == false
    end
  end

  describe "trial_balance/1" do
    test "computes trial balance directly" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, _} = Logistiki.process(event)
      {:ok, tb} = Simulation.trial_balance()
      assert tb.balanced
    end
  end
end
