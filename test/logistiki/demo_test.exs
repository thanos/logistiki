defmodule Logistiki.DemoTest do
  use Logistiki.DataCase, async: false

  alias Logistiki.Demo

  setup do
    Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation)
    on_exit(fn -> Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation) end)
    :ok
  end

  describe "run_demo/0" do
    test "runs the full demo end-to-end and returns a summary map" do
      result = Demo.run_demo()

      assert Map.has_key?(result, :entities)
      assert Map.has_key?(result, :accounts)
      assert Map.has_key?(result, :deposit_result)
      assert Map.has_key?(result, :fee_result)
      assert Map.has_key?(result, :reversal)

      deposit = result.deposit_result
      assert deposit.policy == :cash_deposit
      assert deposit.journal.status == "posted"

      fee = result.fee_result
      assert fee.policy == :corporate_wire_fee

      reversal = result.reversal
      assert reversal.status == :ok
    end
  end
end
