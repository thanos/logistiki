defmodule Logistiki.Accounting.InvariantValidatorTest do
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

  defp journal(key \\ nil), do: %Journal{idempotency_key: key, status: "draft"}

  describe "validate_postings/1" do
    test "accepts a balanced two-sided journal" do
      postings = [
        posting("ASSETS:CASH:USD:NOSTRO", "debit", "100.00"),
        posting("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "credit", "100.00")
      ]

      assert :ok == InvariantValidator.validate_postings(postings)
    end

    test "rejects fewer than two postings" do
      assert {:error, %{code: :unbalanced_journal}} =
               InvariantValidator.validate_postings([
                 posting("ASSETS:CASH:USD:NOSTRO", "debit", "100.00")
               ])
    end

    test "rejects unbalanced journal per currency" do
      postings = [
        posting("ASSETS:CASH:USD:NOSTRO", "debit", "100.00"),
        posting("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "credit", "99.00")
      ]

      assert {:error, %{code: :unbalanced_journal}} = InvariantValidator.validate_postings(postings)
    end

    test "rejects negative amounts" do
      postings = [
        posting("ASSETS:CASH:USD:NOSTRO", "debit", "-100.00"),
        posting("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "credit", "100.00")
      ]

      assert {:error, %{code: :unbalanced_journal}} = InvariantValidator.validate_postings(postings)
    end

    test "rejects missing currency" do
      postings = [
        posting("ASSETS:CASH:USD:NOSTRO", "debit", "100.00", nil),
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

      assert :ok == InvariantValidator.validate_postings(postings)
    end
  end

  describe "validate_accounts/1" do
    test "accepts postings to leaf posting accounts" do
      postings = [
        posting("ASSETS:CASH:USD:NOSTRO", "debit", "100.00"),
        posting("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "credit", "100.00")
      ]

      assert :ok == InvariantValidator.validate_accounts(postings)
    end

    test "rejects postings to a non-existent account" do
      postings = [
        posting("ASSETS:CASH:USD:NOSTRO", "debit", "100.00"),
        posting("LIABILITIES:NOPE", "credit", "100.00")
      ]

      assert {:error, %{code: :account_not_found}} = InvariantValidator.validate_accounts(postings)
    end

    test "rejects postings to a parent (non-leaf) account" do
      # LIABILITIES:CLIENT_DEPOSITS:USD:ACME is an aggregation parent.
      postings = [
        posting("ASSETS:CASH:USD:NOSTRO", "debit", "100.00"),
        posting("LIABILITIES:CLIENT_DEPOSITS:USD:ACME", "credit", "100.00")
      ]

      assert {:error, %{code: :account_not_postable}} =
               InvariantValidator.validate_accounts(postings)
    end
  end

  describe "validate_idempotency/1" do
    test "rejects a duplicate posted idempotency key" do
      alias Logistiki.Accounting

      journal = %Journal{
        idempotency_key: "evt:dup:policy:cash_deposit",
        status: "draft",
        effective_date: ~D[2026-07-07],
        selected_policy: "cash_deposit",
        selected_template: "cash_deposit"
      }

      postings = [
        posting("ASSETS:CASH:USD:NOSTRO", "debit", "100.00"),
        posting("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "credit", "100.00")
      ]

      assert {:ok, _} = Accounting.post_journal(journal, postings)

      assert {:error, %{code: :duplicate_idempotency_key}} =
               InvariantValidator.validate_idempotency("evt:dup:policy:cash_deposit")
    end
  end

  describe "validate_reversal/2" do
    test "rejects a reversal that does not exactly negate" do
      original = [
        posting("ASSETS:CASH:USD:NOSTRO", "debit", "100.00"),
        posting("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "credit", "100.00")
      ]

      bad_reversal = [
        posting("ASSETS:CASH:USD:NOSTRO", "credit", "100.00"),
        posting("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "credit", "100.00")
      ]

      assert {:error, %{code: :unbalanced_journal}} =
               InvariantValidator.validate_reversal(original, bad_reversal)
    end
  end

  describe "reverse_journal/2" do
    alias Logistiki.Accounting

    test "rejects reversal of a draft journal" do
      assert {:error, %{code: :immutable_journal}} =
               Accounting.reverse_journal(%Journal{status: "draft"}, %{})
    end
  end
end
