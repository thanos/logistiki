defmodule Logistiki.EventsTest do
  use Logistiki.DataCase, async: true

  alias Logistiki.Event
  alias Logistiki.Event.{DepositReceived, FeeAssessed, AccountOpened}
  alias Logistiki.Events

  describe "normalize/1" do
    test "normalizes a DepositReceived event" do
      event = %DepositReceived{
        id: "evt_001",
        account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
        cash_account_code: "ASSETS:CASH:USD:NOSTRO",
        amount: Decimal.new("1000.00"),
        currency: "USD",
        occurred_at: ~U[2026-07-07 12:00:00Z],
        effective_date: ~D[2026-07-07],
        source_system: "bank_core",
        source_id: "wire_123"
      }

      assert {:ok, normalized} = Event.normalize(event)
      assert normalized.type == "deposit_received"
      assert normalized.account_code == "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING"
      assert normalized.cash_account_code == "ASSETS:CASH:USD:NOSTRO"
      assert normalized.has_accounting_impact
      assert Decimal.equal?(normalized.amount, Decimal.new("1000.00"))
    end

    test "an AccountOpened event has no accounting impact" do
      event = %AccountOpened{id: "evt_003", account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME"}

      assert {:ok, normalized} = Event.normalize(event)
      refute normalized.has_accounting_impact
    end

    test "a FeeAssessed event carries its fee_type" do
      event = %FeeAssessed{
        id: "evt_002",
        account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
        fee_income_account_code: "INCOME:FEES:WIRE",
        amount: Decimal.new("25.00"),
        currency: "USD",
        fee_type: "wire_fee"
      }

      assert {:ok, normalized} = Event.normalize(event)
      assert normalized.fee_type == "wire_fee"
      assert normalized.type == "fee_assessed"
    end
  end

  describe "persist/1" do
    test "persists a normalized business event" do
      event = %DepositReceived{
        id: "evt_001",
        account_code: "LIAB:ACME",
        cash_account_code: "ASSETS:CASH",
        amount: Decimal.new("1000.00"),
        currency: "USD",
        occurred_at: ~U[2026-07-07 12:00:00Z],
        effective_date: ~D[2026-07-07],
        source_system: "bank_core",
        source_id: "wire_123"
      }

      assert {:ok, persisted} = Events.persist(event)
      assert persisted.event_type == "deposit_received"
      assert persisted.status == "normalized"
      assert persisted.normalized_payload["account_code"] == "LIAB:ACME"
    end
  end
end
