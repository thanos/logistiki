defmodule Logistiki.Accounting.PostingBuilderTest do
  use ExUnit.Case, async: true

  alias Logistiki.Accounting.Posting
  alias Logistiki.Accounting.PostingBuilder
  alias Logistiki.Error

  @template_postings [
    %{
      sequence: 1,
      direction: :debit,
      role: :cash_account,
      amount_var: :event_amount,
      currency_var: :event_currency
    },
    %{
      sequence: 2,
      direction: :credit,
      role: :client_liability_account,
      amount_var: :event_amount,
      currency_var: :event_currency
    }
  ]

  @roles %{cash_account: "ASSETS:CASH:USD:NOSTRO", client_liability_account: "LIAB:ACME"}

  describe "build/5" do
    test "builds postings from template and roles" do
      {:ok, postings} =
        PostingBuilder.build(@template_postings, @roles, Decimal.new("100"), "USD", nil)

      assert length(postings) == 2
      [p1, p2] = postings
      assert p1.account_code == "ASSETS:CASH:USD:NOSTRO"
      assert p1.debit_credit == "debit"
      assert p2.account_code == "LIAB:ACME"
      assert p2.debit_credit == "credit"
    end

    test "sorts postings by sequence" do
      reversed = Enum.reverse(@template_postings)
      {:ok, postings} = PostingBuilder.build(reversed, @roles, Decimal.new("100"), "USD", nil)
      assert hd(postings).sequence == 1
    end

    test "includes role in metadata" do
      {:ok, postings} =
        PostingBuilder.build(@template_postings, @roles, Decimal.new("100"), "USD", nil)

      assert hd(postings).metadata[:role] == "cash_account"
    end

    test "returns error when amount is nil" do
      assert {:error, %Error{code: :invalid_template}} =
               PostingBuilder.build(@template_postings, @roles, nil, "USD", nil)
    end

    test "returns error when amount is zero" do
      assert {:error, %Error{code: :invalid_template, message: msg}} =
               PostingBuilder.build(@template_postings, @roles, Decimal.new("0"), "USD", nil)

      assert String.contains?(msg, "positive")
    end

    test "returns error when amount is negative" do
      assert {:error, %Error{code: :invalid_template}} =
               PostingBuilder.build(@template_postings, @roles, Decimal.new("-1"), "USD", nil)
    end

    test "returns error when currency is nil" do
      assert {:error, %Error{code: :invalid_template}} =
               PostingBuilder.build(@template_postings, @roles, Decimal.new("100"), nil, nil)
    end

    test "returns error when a role is missing" do
      roles = %{cash_account: "ASSETS:CASH:USD:NOSTRO"}

      assert {:error, %Error{code: :account_not_found}} =
               PostingBuilder.build(@template_postings, roles, Decimal.new("100"), "USD", nil)
    end

    test "returns error when a role maps to nil" do
      roles = %{cash_account: nil, client_liability_account: "LIAB"}

      assert {:error, %Error{code: :account_not_found}} =
               PostingBuilder.build(@template_postings, roles, Decimal.new("100"), "USD", nil)
    end
  end

  describe "build_reversals/2" do
    test "flips debit to credit" do
      postings = [
        %Posting{
          account_code: "A",
          debit_credit: "debit",
          amount: Decimal.new("100"),
          currency: "USD",
          sequence: 1,
          id: 10
        }
      ]

      [reversal] = PostingBuilder.build_reversals(postings, nil)
      assert reversal.debit_credit == "credit"
      assert reversal.account_code == "A"
      assert reversal.amount == Decimal.new("100")
      assert reversal.memo == "reversal"
    end

    test "flips credit to debit" do
      postings = [
        %Posting{
          account_code: "A",
          debit_credit: "credit",
          amount: Decimal.new("50"),
          currency: "EUR",
          sequence: 1,
          id: 20
        }
      ]

      [reversal] = PostingBuilder.build_reversals(postings, nil)
      assert reversal.debit_credit == "debit"
      assert reversal.currency == "EUR"
    end

    test "includes reversal_of_posting in metadata" do
      postings = [
        %Posting{
          account_code: "A",
          debit_credit: "debit",
          amount: Decimal.new("100"),
          currency: "USD",
          sequence: 1,
          id: 99,
          metadata: %{}
        }
      ]

      [reversal] = PostingBuilder.build_reversals(postings, nil)
      assert reversal.metadata["reversal_of_posting"] == 99
    end

    test "preserves existing metadata when adding reversal reference" do
      postings = [
        %Posting{
          account_code: "A",
          debit_credit: "debit",
          amount: Decimal.new("100"),
          currency: "USD",
          sequence: 1,
          id: 99,
          metadata: %{"role" => "cash"}
        }
      ]

      [reversal] = PostingBuilder.build_reversals(postings, nil)
      assert reversal.metadata["role"] == "cash"
      assert reversal.metadata["reversal_of_posting"] == 99
    end

    test "handles nil metadata gracefully" do
      postings = [
        %Posting{
          account_code: "A",
          debit_credit: "debit",
          amount: Decimal.new("100"),
          currency: "USD",
          sequence: 1,
          id: 1,
          metadata: nil
        }
      ]

      [reversal] = PostingBuilder.build_reversals(postings, nil)
      assert reversal.metadata["reversal_of_posting"] == 1
    end
  end
end
