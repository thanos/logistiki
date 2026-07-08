defmodule Logistiki.Events.ContextTest do
  use Logistiki.DataCase, async: true

  alias Logistiki.Event.DepositReceived
  alias Logistiki.Events
  alias Logistiki.Events.BusinessEvent

  describe "normalize/1" do
    test "normalizes a DepositReceived event" do
      event = %DepositReceived{
        id: "evt_n1",
        account_code: "LIAB:ACME",
        cash_account_code: "ASSETS:CASH",
        amount: Decimal.new("100.00"),
        currency: "USD"
      }

      assert {:ok, normalized} = Events.normalize(event)
      assert normalized.type == "deposit_received"
    end
  end

  describe "persist/1" do
    test "persists a business event with normalized payload" do
      event = %DepositReceived{
        id: "evt_p1",
        account_code: "LIAB:ACME",
        cash_account_code: "ASSETS:CASH",
        amount: Decimal.new("100.00"),
        currency: "USD",
        occurred_at: ~U[2026-07-07 12:00:00Z],
        effective_date: ~D[2026-07-07]
      }

      assert {:ok, persisted} = Events.persist(event)
      assert persisted.event_type == "deposit_received"
      assert persisted.status == "normalized"
      assert persisted.normalized_payload["account_code"] == "LIAB:ACME"
    end
  end

  describe "get_event!/1" do
    test "fetches a persisted event by id" do
      event = %DepositReceived{
        id: "evt_g1",
        account_code: "LIAB",
        amount: Decimal.new("1.00"),
        currency: "USD"
      }

      {:ok, persisted} = Events.persist(event)
      found = Events.get_event!(persisted.id)
      assert found.id == persisted.id
    end
  end

  describe "list_events/1" do
    test "lists events filtered by event_type" do
      event = %DepositReceived{
        id: "evt_l1",
        account_code: "LIAB",
        amount: Decimal.new("1.00"),
        currency: "USD"
      }

      Events.persist(event)
      events = Events.list_events(event_type: "deposit_received")
      assert Enum.any?(events, &(&1.event_type == "deposit_received"))
    end

    test "lists events filtered by status" do
      event = %DepositReceived{
        id: "evt_l2",
        account_code: "LIAB",
        amount: Decimal.new("1.00"),
        currency: "USD"
      }

      Events.persist(event)
      events = Events.list_events(status: "normalized")
      assert Enum.all?(events, &(&1.status == "normalized"))
    end
  end

  describe "update_status/3" do
    test "updates the status of a persisted event" do
      event = %DepositReceived{
        id: "evt_u1",
        account_code: "LIAB",
        amount: Decimal.new("1.00"),
        currency: "USD"
      }

      {:ok, persisted} = Events.persist(event)
      assert {:ok, updated} = Events.update_status(persisted, :processed)
      assert updated.status == "processed"
    end

    test "updates with explanation" do
      event = %DepositReceived{
        id: "evt_u2",
        account_code: "LIAB",
        amount: Decimal.new("1.00"),
        currency: "USD"
      }

      {:ok, persisted} = Events.persist(event)
      {:ok, updated} = Events.update_status(persisted, :blocked, %{reason: :sanctions})
      assert updated.status == "blocked"
      assert updated.explanation == %{reason: :sanctions}
    end
  end

  describe "BusinessEvent.statuses/0" do
    test "returns all statuses" do
      statuses = BusinessEvent.statuses()
      assert :received in statuses
      assert :normalized in statuses
      assert :processed in statuses
      assert :blocked in statuses
    end
  end
end
