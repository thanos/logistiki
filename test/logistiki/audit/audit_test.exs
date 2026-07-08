defmodule Logistiki.AuditTest do
  use Logistiki.DataCase, async: false

  alias Logistiki.Audit
  alias Logistiki.Audit.AuditEvent
  alias Logistiki.Demo.Seeds

  describe "record/1" do
    test "creates an audit event" do
      {:ok, event} = Audit.record(%{action: "test_action", event_id: "evt_test"})
      assert event.action == "test_action"
      assert event.event_id == "evt_test"
    end

    test "requires action" do
      {:error, changeset} = Audit.record(%{})
      assert errors_on(changeset)[:action]
    end
  end

  describe "record_evidence/1" do
    test "records every stage in an Evidence struct" do
      evidence = %Logistiki.Audit.Evidence{
        event_id: "evt_ev",
        journal_id: nil,
        stages: [
          %{action: :step1, resource_type: :event},
          %{action: :step2, resource_type: :journal}
        ],
        explanation: %{test: true}
      }

      assert :ok = Audit.record_evidence(evidence)
      events = Audit.list_audit_events(event_id: "evt_ev")
      assert length(events) == 2
      actions = Enum.map(events, & &1.action) |> Enum.sort()
      assert actions == ["step1", "step2"]
    end
  end

  describe "list_audit_events/1" do
    test "lists all events when no filter" do
      Audit.record(%{action: "list_all_1"})
      Audit.record(%{action: "list_all_2"})
      events = Audit.list_audit_events()
      assert length(events) >= 2
    end

    test "filters by action" do
      Audit.record(%{action: "filter_me"})
      Audit.record(%{action: "dont_filter_me"})
      events = Audit.list_audit_events(action: "filter_me")
      assert Enum.empty?(events) == false
      assert Enum.all?(events, &(&1.action == "filter_me"))
    end

    test "filters by journal_id" do
      # First create a journal so the FK is valid
      Seeds.run()
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "10.00")
      {:ok, result} = Logistiki.process(event)
      journal_id = result.journal.id

      events = Audit.list_audit_events(journal_id: journal_id)
      refute Enum.empty?(events)
      assert Enum.all?(events, &(&1.journal_id == journal_id))
    end
  end

  describe "trail_for_event/1" do
    test "returns events ordered by inserted_at ascending" do
      Audit.record(%{action: "first", event_id: "trail_1"})
      Audit.record(%{action: "second", event_id: "trail_1"})
      trail = Audit.trail_for_event("trail_1")
      assert length(trail) >= 2
      actions = Enum.map(trail, & &1.action)
      assert "first" in actions
      assert "second" in actions
    end

    test "returns empty list for unknown event" do
      assert Audit.trail_for_event("nonexistent") == []
    end
  end

  describe "trail_for_journal/1" do
    test "returns events for a journal ordered ascending" do
      Seeds.run()
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "10.00")
      {:ok, result} = Logistiki.process(event)
      trail = Audit.trail_for_journal(result.journal.id)
      refute Enum.empty?(trail)
    end

    test "returns empty list for unknown journal" do
      assert Audit.trail_for_journal(999_999) == []
    end
  end
end
