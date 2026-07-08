defmodule Logistiki.Knowledge.PolicySelectorTest do
  use Logistiki.DataCase, async: true

  alias Logistiki.Event.Normalized
  alias Logistiki.Knowledge.PolicySelector

  describe "select/1" do
    test "returns the policy for a deposit event" do
      event =
        Normalized.new(%{
          type: "deposit_received",
          amount: Decimal.new("1000.00"),
          currency: "USD",
          account_code: "LIAB:ACME",
          cash_account_code: "ASSETS:CASH",
          entity_type: "corporate"
        })

      assert {:ok, :cash_deposit} = PolicySelector.select(event)
    end

    test "returns the policy for a corporate wire fee" do
      event =
        Normalized.new(%{
          type: "fee_assessed",
          amount: Decimal.new("25.00"),
          currency: "USD",
          fee_type: "wire_fee",
          entity_type: "corporate"
        })

      assert {:ok, :corporate_wire_fee} = PolicySelector.select(event)
    end

    test "returns :no_policy_found for an unknown event type" do
      event = Normalized.new(%{type: "mystery", amount: Decimal.new("1.00")})
      assert {:error, :no_policy_found} = PolicySelector.select(event)
    end

    test "returns :approval_required for amounts above threshold" do
      event =
        Normalized.new(%{
          type: "deposit_received",
          amount: Decimal.new("100000.00"),
          currency: "USD",
          account_code: "LIAB:ACME",
          cash_account_code: "ASSETS:CASH"
        })

      assert {:error, :approval_required} = PolicySelector.select(event)
    end
  end
end
