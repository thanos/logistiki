defmodule LogistikiTest do
  use ExUnit.Case, async: true

  alias Logistiki

  setup do
    Code.ensure_loaded(Logistiki)
    :ok
  end

  describe "public API surface" do
    test "process/1, query, and admin functions are exported" do
      assert function_exported?(Logistiki, :process, 1)
      assert function_exported?(Logistiki, :process, 2)
      assert function_exported?(Logistiki, :balance, 1)
      assert function_exported?(Logistiki, :statement, 1)
      assert function_exported?(Logistiki, :trial_balance, 0)
      assert function_exported?(Logistiki, :general_ledger, 0)
      assert function_exported?(Logistiki, :balance_sheet, 0)
      assert function_exported?(Logistiki, :income_statement, 0)
      assert function_exported?(Logistiki, :ledger_backend, 0)
    end
  end
end
