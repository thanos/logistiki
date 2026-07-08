defmodule Logistiki.NormalizedTest do
  use ExUnit.Case, async: true

  alias Logistiki.Event.Normalized

  describe "new/1" do
    test "builds a normalized event from a map" do
      n = Normalized.new(%{id: "evt_1", type: "deposit_received", amount: Decimal.new("100")})
      assert n.id == "evt_1"
      assert n.type == "deposit_received"
      assert n.amount == Decimal.new("100")
    end

    test "builds from keyword list" do
      n = Normalized.new(id: "evt_2", type: "fee_assessed")
      assert n.id == "evt_2"
      assert n.type == "fee_assessed"
    end
  end

  describe "to_map/1" do
    test "converts to a string-keyed map" do
      n =
        Normalized.new(%{
          id: "evt_1",
          type: "deposit",
          amount: Decimal.new("100.00"),
          currency: "USD"
        })

      map = Normalized.to_map(n)
      assert map["id"] == "evt_1"
      assert map["type"] == "deposit"
      assert map["amount"] == "100.00"
      assert map["currency"] == "USD"
    end

    test "omits nil fields" do
      n = Normalized.new(%{id: "evt_1", type: "deposit"})
      map = Normalized.to_map(n)
      refute Map.has_key?(map, "account_code")
    end

    test "includes default fields" do
      n = Normalized.new(%{id: "x", type: "y"})
      map = Normalized.to_map(n)
      assert map["has_accounting_impact"] == true
      assert map["metadata"] == %{}
    end

    test "encodes DateTime to ISO 8601" do
      n = Normalized.new(%{type: "t", occurred_at: ~U[2026-07-07 12:00:00Z]})
      map = Normalized.to_map(n)
      assert map["occurred_at"] == "2026-07-07T12:00:00Z"
    end

    test "encodes Date to ISO 8601" do
      n = Normalized.new(%{type: "t", effective_date: ~D[2026-07-07]})
      map = Normalized.to_map(n)
      assert map["effective_date"] == "2026-07-07"
    end

    test "encodes nested maps" do
      n = Normalized.new(%{type: "t", metadata: %{nested_key: "val"}})
      map = Normalized.to_map(n)
      assert map["metadata"]["nested_key"] == "val"
    end
  end
end
