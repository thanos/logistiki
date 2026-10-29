defmodule Logistiki.V011.OpsAndPropertiesTest do
  @moduledoc "L11-21..L11-22 plus StreamData durability properties."
  use Logistiki.V011Case
  use ExUnitProperties

  alias Logistiki.Accounting.InvariantValidator
  alias Logistiki.Accounting.Posting

  # L11-21 Durable state and idempotency survive reconnect-style re-lookup
  test "L11-21 durable financial state and idempotency survive reconnect-style lookup" do
    event = deposit("21.00", id: "l11_21")
    assert {:ok, result} = Logistiki.process(event)
    journal_id = result.journal.id

    # Simulate the host losing the in-memory result and reconciling via lookup.
    assert {:ok, looked} = Logistiki.lookup_outcome(event_id: "l11_21")
    assert looked.journal.id == journal_id

    assert {:ok, replay} = Logistiki.process(event)
    assert replay.explanation[:outcome] == :already_processed
    assert replay.journal.id == journal_id
  end

  # L11-22 App embedding smoke test
  test "L11-22 host finds packaged migrations and processes without private startup" do
    path = Application.app_dir(:logistiki, "priv/repo/migrations")
    assert File.dir?(path)
    assert Enum.any?(File.ls!(path), &String.ends_with?(&1, ".exs"))

    # Repo is already supervised by the :logistiki application — the embedding
    # contract is that hosts start the app (or Repo) and run these migrations.
    event = deposit("22.00", id: "l11_22_embed")
    assert {:ok, %{journal: %{status: "posted"}}} = Logistiki.process(event)
    assert provenance_count("l11_22_embed") == 1
  end

  property "balanced postings validate; unbalanced postings are rejected" do
    check all(
            amount <- map(integer(1..9999), &Decimal.new(&1)),
            unbalanced? <- boolean()
          ) do
      credit =
        if unbalanced?,
          do: Decimal.add(amount, Decimal.new(1)),
          else: amount

      postings = [
        %Posting{
          account_code: "ASSETS:CASH:USD:NOSTRO",
          debit_credit: "debit",
          amount: amount,
          currency: "USD",
          sequence: 1
        },
        %Posting{
          account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
          debit_credit: "credit",
          amount: credit,
          currency: "USD",
          sequence: 2
        }
      ]

      result = InvariantValidator.validate_postings(postings)

      if unbalanced? do
        assert match?({:error, %{code: :unbalanced_journal}}, result)
      else
        assert result == :ok
      end
    end
  end

  property "duplicate deposit stream does not multiply postings" do
    check all(amount <- map(integer(1..100), &Decimal.new/1)) do
      id = "l11_prop_#{System.unique_integer([:positive])}"
      event = deposit(Decimal.to_string(amount), id: id)
      before = journal_count()

      assert {:ok, _} = Logistiki.process(event)
      assert {:ok, replay} = Logistiki.process(event)
      assert replay.explanation[:outcome] == :already_processed
      assert journal_count() == before + 1
    end
  end
end
