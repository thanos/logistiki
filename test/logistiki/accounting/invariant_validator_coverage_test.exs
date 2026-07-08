defmodule Logistiki.Accounting.InvariantValidatorCoverageTest do
  use Logistiki.DataCase, async: true

  alias Logistiki.Accounting.{InvariantValidator, Journal, Posting}
  alias Logistiki.Demo.Seeds

  setup do
    Seeds.run()
    :ok
  end

  defp posting(code, dir, amount, cur \\ "USD") do
    %Posting{
      account_code: code,
      debit_credit: dir,
      amount: Decimal.new(amount),
      currency: cur,
      sequence: 1
    }
  end

  describe "validate_postings/1 edge cases" do
    test "rejects invalid debit_credit direction" do
      postings = [
        posting("ASSETS:CASH:USD:NOSTRO", "wrong", "100.00"),
        posting("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "credit", "100.00")
      ]

      assert {:error, %{code: :unbalanced_journal}} = InvariantValidator.validate_postings(postings)
    end

    test "balances independently per currency" do
      postings = [
        posting("ASSETS:CASH:USD:NOSTRO", "debit", "100.00", "USD"),
        posting("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "credit", "100.00", "USD"),
        posting("SUSPENSE:USD", "debit", "50.00", "EUR"),
        posting("SUSPENSE:USD", "credit", "50.00", "EUR")
      ]

      assert :ok = InvariantValidator.validate_postings(postings)
    end

    test "rejects unbalanced across currencies" do
      postings = [
        posting("ASSETS:CASH:USD:NOSTRO", "debit", "100.00", "USD"),
        posting("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "credit", "100.00", "EUR")
      ]

      assert {:error, %{code: :unbalanced_journal}} = InvariantValidator.validate_postings(postings)
    end
  end

  describe "validate_accounts/1 edge cases" do
    test "accepts empty postings list" do
      assert :ok = InvariantValidator.validate_accounts([])
    end
  end

  describe "validate_idempotency/1" do
    test "passes for nil key" do
      assert :ok = InvariantValidator.validate_idempotency(nil)
    end

    test "passes for a unique key" do
      assert :ok = InvariantValidator.validate_idempotency("unique_key_test_123")
    end
  end

  describe "validate_reversal/2" do
    test "rejects reversal with wrong count" do
      original = [posting("A", "debit", "100"), posting("B", "credit", "100")]
      bad = [posting("A", "credit", "100")]

      assert {:error, %{code: :unbalanced_journal}} =
               InvariantValidator.validate_reversal(original, bad)
    end

    test "rejects reversal with wrong amount" do
      original = [posting("A", "debit", "100"), posting("B", "credit", "100")]
      bad = [posting("A", "credit", "99"), posting("B", "debit", "100")]

      assert {:error, %{code: :unbalanced_journal}} =
               InvariantValidator.validate_reversal(original, bad)
    end

    test "rejects reversal with wrong currency" do
      original = [posting("A", "debit", "100", "USD"), posting("B", "credit", "100", "USD")]
      bad = [posting("A", "credit", "100", "EUR"), posting("B", "debit", "100", "EUR")]

      assert {:error, %{code: :unbalanced_journal}} =
               InvariantValidator.validate_reversal(original, bad)
    end

    test "accepts exact reversal" do
      original = [posting("A", "debit", "100"), posting("B", "credit", "100")]
      reversal = [posting("A", "credit", "100"), posting("B", "debit", "100")]

      assert :ok = InvariantValidator.validate_reversal(original, reversal)
    end
  end

  describe "validate/2 with nil journal" do
    test "validates with no journal context" do
      postings = [
        posting("ASSETS:CASH:USD:NOSTRO", "debit", "100.00"),
        posting("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "credit", "100.00")
      ]

      assert :ok = InvariantValidator.validate(%Journal{idempotency_key: nil}, postings)
    end
  end
end
