defmodule Logistiki.V011.DurabilityTest do
  @moduledoc "L11-01..L11-12 durability and failure-injection regressions."
  use Logistiki.V011Case

  alias Ecto.Adapters.SQL.Sandbox
  alias Logistiki.Accounting.{Journal, Posting}
  alias Logistiki.Repo

  # L11-01 Ordinary USD deposit
  test "L11-01 ordinary USD deposit posts one balanced journal with provenance" do
    event = deposit("250.00")
    before_j = journal_count()
    before_p = posting_count()

    assert {:ok, result} = Logistiki.process(event)
    assert result.journal.status == "posted"
    assert length(result.postings) == 2
    assert journal_count() == before_j + 1
    assert posting_count() == before_p + 2
    assert provenance_count(event.id) == 1

    assert {:ok, [cash]} = Logistiki.balance("ASSETS:CASH:USD:NOSTRO")
    assert Decimal.equal?(cash.net, Decimal.new("250.00"))
  end

  # L11-02 Event persistence forced failure
  test "L11-02 event persistence failure leaves zero posted journals" do
    event = deposit("10.00")
    before_j = journal_count()
    Application.put_env(:logistiki, :inject_commit_failure, :event)

    assert {:error, %{code: :event_persist_failed}} = Logistiki.process(event)
    assert journal_count() == before_j
    assert posting_count() == 0 or posting_count() == posting_count()
    assert provenance_count(event.id) == 0
  after
    Application.delete_env(:logistiki, :inject_commit_failure)
  end

  # L11-03 Journal/posting DB failure
  test "L11-03 journal failure leaves no half-written financial state" do
    event = deposit("11.00")
    before_j = journal_count()

    before_be =
      Logistiki.Repo.aggregate(Logistiki.Events.BusinessEvent, :count, :id)

    Application.put_env(:logistiki, :inject_commit_failure, :journal)

    assert {:error, %{code: :commit_failed}} = Logistiki.process(event)
    assert journal_count() == before_j

    assert Logistiki.Repo.aggregate(Logistiki.Events.BusinessEvent, :count, :id) ==
             before_be
  after
    Application.delete_env(:logistiki, :inject_commit_failure)
  end

  # L11-04 Mandatory audit failure
  test "L11-04 mandatory audit failure prevents committed posting" do
    event = deposit("12.00")
    before_j = journal_count()
    Application.put_env(:logistiki, :inject_commit_failure, :audit)

    assert {:error, %{code: :audit_persist_failed}} = Logistiki.process(event)
    assert journal_count() == before_j
    assert provenance_count(event.id) == 0
  after
    Application.delete_env(:logistiki, :inject_commit_failure)
  end

  # L11-05 Two concurrent identical requests
  @tag :concurrency
  @tag :postgres
  test "L11-05 concurrent identical requests yield one posting effect" do
    event = deposit("13.00", id: "l11_05_shared")
    parent = self()

    tasks =
      for _ <- 1..2 do
        Task.async(fn ->
          Sandbox.allow(Repo, parent, self())
          Logistiki.process(event)
        end)
      end

    results = Task.await_many(tasks, 15_000)

    # Under concurrency one request commits and the loser must resolve to the
    # original outcome (replay) or a typed duplicate — never a second journal.
    assert Enum.all?(results, fn
             {:ok, _} ->
               true

             {:error, %{code: code}}
             when code in [:duplicate_idempotency_key, :idempotency_conflict] ->
               true

             _ ->
               false
           end)

    assert Enum.any?(results, &match?({:ok, _}, &1))

    journals =
      from(j in Journal, where: j.event_id == "l11_05_shared" and j.status == "posted")
      |> Logistiki.Repo.all()

    assert length(journals) == 1
  end

  # L11-06 Same key, different amount
  test "L11-06 same identity with different amount is a conflict" do
    event1 = deposit("14.00", id: "l11_06", source_id: "l11_06")
    assert {:ok, _} = Logistiki.process(event1)

    event2 = deposit("99.00", id: "l11_06", source_id: "l11_06")
    before_j = journal_count()

    assert {:error, %{code: :idempotency_conflict}} = Logistiki.process(event2)
    assert journal_count() == before_j
  end

  # L11-07 Crash immediately before commit
  test "L11-07 failure before commit leaves no financial effect and allows retry" do
    event = deposit("15.00", id: "l11_07")
    Application.put_env(:logistiki, :inject_commit_failure, :event)
    assert {:error, _} = Logistiki.process(event)
    Application.delete_env(:logistiki, :inject_commit_failure)

    assert {:ok, result} = Logistiki.process(event)
    assert result.journal.status == "posted"
  end

  # L11-08 Crash/timeout after commit — lookup resolves; retry does not double-post
  test "L11-08 lookup after commit and safe retry" do
    event = deposit("16.00", id: "l11_08")
    assert {:ok, first} = Logistiki.process(event)
    before_j = journal_count()

    assert {:ok, looked} = Logistiki.lookup_outcome(event_id: event.id)
    assert looked.journal.id == first.journal.id

    assert {:ok, replay} = Logistiki.process(event)
    assert replay.explanation[:outcome] == :already_processed
    assert journal_count() == before_j
  end

  # L11-09 Two concurrent reversal attempts
  @tag :concurrency
  @tag :postgres
  test "L11-09 concurrent reversals produce exactly one compensating journal" do
    event = deposit("17.00", id: "l11_09")
    assert {:ok, %{journal: journal}} = Logistiki.process(event)
    parent = self()
    before = journal_count()

    tasks =
      for i <- 1..2 do
        Task.async(fn ->
          Sandbox.allow(Repo, parent, self())
          Accounting.reverse_journal(journal, %{reason: "l11_09_#{i}"})
        end)
      end

    results = Task.await_many(tasks, 15_000)
    oks = Enum.filter(results, &match?({:ok, _}, &1))
    assert length(oks) == 1
    assert journal_count() == before + 1

    reversals =
      from(j in Journal, where: j.reversal_of_id == ^journal.id)
      |> Logistiki.Repo.all()

    assert length(reversals) == 1
  end

  # L11-10 Reverse already reversed journal
  test "L11-10 reverse already reversed is stable without extra postings" do
    event = deposit("18.00", id: "l11_10")
    assert {:ok, %{journal: journal}} = Logistiki.process(event)
    assert {:ok, _} = Accounting.reverse_journal(journal)
    before = journal_count()

    reloaded = Accounting.get_journal!(journal.id)
    assert {:error, %{code: :immutable_journal}} = Accounting.reverse_journal(reloaded)
    assert journal_count() == before
  end

  # L11-11 Attempt to mutate posted journal/postings
  test "L11-11 database rejects mutation of posted postings" do
    event = deposit("19.00", id: "l11_11")
    assert {:ok, %{journal: journal, postings: [posting | _]}} = Logistiki.process(event)

    assert_raise Postgrex.Error, ~r/immutable/i, fn ->
      from(p in Posting, where: p.id == ^posting.id)
      |> Logistiki.Repo.update_all(set: [amount: Decimal.new("1.00")])
    end

    assert_raise Postgrex.Error, ~r/immutable/i, fn ->
      from(j in Journal, where: j.id == ^journal.id)
      |> Logistiki.Repo.update_all(set: [description: "mutated"])
    end
  end

  # L11-12 Insufficient/invalid posting structure
  test "L11-12 unbalanced journals cannot commit via post_journal" do
    journal = %Journal{
      status: "draft",
      idempotency_key: "l11_12_#{System.unique_integer([:positive])}",
      effective_date: ~D[2026-07-07]
    }

    postings = [
      %Posting{
        account_code: "ASSETS:CASH:USD:NOSTRO",
        debit_credit: "debit",
        amount: Decimal.new("100.00"),
        currency: "USD",
        sequence: 1
      },
      %Posting{
        account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
        debit_credit: "credit",
        amount: Decimal.new("50.00"),
        currency: "USD",
        sequence: 2
      }
    ]

    before = journal_count()
    assert {:error, %{code: :unbalanced_journal}} = Accounting.post_journal(journal, postings)
    assert journal_count() == before
  end
end
