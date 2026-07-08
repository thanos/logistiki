defmodule Logistiki.Accounting.JournalTest do
  use ExUnit.Case, async: true

  alias Logistiki.Accounting.{Journal, Posting}

  describe "statuses/0" do
    test "returns all statuses" do
      assert :draft in Journal.statuses()
      assert :posted in Journal.statuses()
      assert :reversed in Journal.statuses()
      assert :rejected in Journal.statuses()
      assert :validated in Journal.statuses()
    end
  end

  describe "posted?/1" do
    test "true when status is posted" do
      assert Journal.posted?(%Journal{status: "posted"})
    end

    test "false when status is draft" do
      refute Journal.posted?(%Journal{status: "draft"})
    end

    test "false when status is reversed" do
      refute Journal.posted?(%Journal{status: "reversed"})
    end

    test "false for non-Journal input" do
      refute Journal.posted?("posted")
    end
  end

  describe "reversal?/1" do
    test "true when reversal_of_id is set" do
      assert Journal.reversal?(%Journal{reversal_of_id: 5})
    end

    test "false when reversal_of_id is nil" do
      refute Journal.reversal?(%Journal{reversal_of_id: nil})
    end
  end
end

defmodule Logistiki.Accounting.PostingTest do
  use ExUnit.Case, async: true

  alias Logistiki.Accounting.Posting

  describe "directions/0" do
    test "returns debit and credit" do
      assert :debit in Posting.directions()
      assert :credit in Posting.directions()
    end
  end

  describe "debit?/1" do
    test "true for a debit posting" do
      assert Posting.debit?(%Posting{debit_credit: "debit"})
    end

    test "false for a credit posting" do
      refute Posting.debit?(%Posting{debit_credit: "credit"})
    end
  end

  describe "credit?/1" do
    test "true for a credit posting" do
      assert Posting.credit?(%Posting{debit_credit: "credit"})
    end

    test "false for a debit posting" do
      refute Posting.credit?(%Posting{debit_credit: "debit"})
    end
  end

  describe "signed_amount/1" do
    test "returns positive amount for debit" do
      p = %Posting{amount: Decimal.new("100"), debit_credit: "debit"}
      assert Posting.signed_amount(p) == Decimal.new("100")
    end

    test "returns negative amount for credit" do
      p = %Posting{amount: Decimal.new("100"), debit_credit: "credit"}
      assert Posting.signed_amount(p) == Decimal.new("-100")
    end
  end
end
