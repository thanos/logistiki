defmodule Logistiki.Accounting.ContextTest do
  use Logistiki.DataCase, async: false

  alias Logistiki.Accounting
  alias Logistiki.Accounting.{Journal, Posting}
  alias Logistiki.Demo.Seeds

  setup do
    {entities, accounts} = Seeds.run()
    Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation)
    %{entities: entities, accounts: accounts}
  end

  describe "get_journal!/1" do
    test "fetches a journal by id with postings preloaded" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, result} = Logistiki.process(event)
      journal = Accounting.get_journal!(result.journal.id)
      assert journal.id == result.journal.id
      assert length(journal.postings) == 2
    end
  end

  describe "get_journal/1" do
    test "returns {:ok, journal} when found" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, result} = Logistiki.process(event)
      assert {:ok, journal} = Accounting.get_journal(result.journal.id)
      assert journal.id == result.journal.id
    end

    test "returns {:error, :not_found} when not found" do
      assert {:error, :not_found} = Accounting.get_journal(999_999)
    end
  end

  describe "list_postings/1" do
    test "lists postings for a journal ordered by sequence" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, result} = Logistiki.process(event)
      postings = Accounting.list_postings(result.journal)
      assert length(postings) == 2
      assert hd(postings).sequence == 1
    end
  end

  describe "list_journals/1" do
    test "lists journals filtered by status" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, result} = Logistiki.process(event)
      posted = Accounting.list_journals(status: "posted")
      assert Enum.any?(posted, &(&1.id == result.journal.id))
    end

    test "lists journals filtered by event_id" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, result} = Logistiki.process(event)
      journals = Accounting.list_journals(event_id: event.id)
      assert Enum.any?(journals, &(&1.event_id == event.id))
    end
  end

  describe "post_journal/2" do
    test "rejects posting a non-draft journal" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, result} = Logistiki.process(event)
      assert {:error, %{code: :immutable_journal}} = Accounting.post_journal(result.journal, [])
    end
  end

  describe "reverse_journal/2" do
    test "rejects reversal of a draft journal" do
      assert {:error, %{code: :immutable_journal}} =
               Accounting.reverse_journal(%Journal{status: "draft"}, %{})
    end

    test "reverses a posted journal and marks original reversed" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "100.00")
      {:ok, result} = Logistiki.process(event)

      assert {:ok, reversal_result} = Accounting.reverse_journal(result.journal, %{reason: "test"})
      assert reversal_result.status == "posted"
      assert reversal_result.reversal_of_id == result.journal.id

      original = Accounting.get_journal!(result.journal.id)
      assert original.status == "reversed"
    end
  end

  describe "draft_journal/1" do
    test "builds a changeset for a journal" do
      cs = Accounting.draft_journal(%{status: "draft", description: "test"})
      assert cs.valid?
    end
  end
end
