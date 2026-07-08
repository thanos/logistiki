defmodule Logistiki.Ledger.BeancountMapperTest do
  use ExUnit.Case, async: true

  alias Logistiki.Accounting.{Journal, Posting}
  alias Logistiki.Ledger.BeancountMapper
  alias Logistiki.VirtualAccounts.VirtualAccount

  defp account(code, type) do
    %VirtualAccount{code: code, account_type: type, currency: "USD"}
  end

  describe "to_beancount_account/1" do
    test "maps asset to Assets root" do
      assert BeancountMapper.to_beancount_account(account("ASSETS:CASH:USD:NOSTRO", "asset")) ==
               "Assets:CASH:USD:NOSTRO"
    end

    test "maps liability to Liabilities root" do
      assert BeancountMapper.to_beancount_account(account("LIABILITIES:DEPOSITS", "liability")) ==
               "Liabilities:DEPOSITS"
    end

    test "maps client to Liabilities root" do
      assert BeancountMapper.to_beancount_account(account("LIABILITIES:ACME", "client")) ==
               "Liabilities:ACME"
    end

    test "maps equity to Equity root" do
      assert BeancountMapper.to_beancount_account(account("EQUITY:OPENING", "equity")) ==
               "Equity:OPENING"
    end

    test "maps income to Income root" do
      assert BeancountMapper.to_beancount_account(account("INCOME:FEES:WIRE", "income")) ==
               "Income:FEES:WIRE"
    end

    test "maps fee to Income root" do
      assert BeancountMapper.to_beancount_account(account("INCOME:FEES:WIRE", "fee")) ==
               "Income:FEES:WIRE"
    end

    test "maps expense to Expenses root" do
      assert BeancountMapper.to_beancount_account(account("EXPENSES:INTEREST", "expense")) ==
               "Expenses:INTEREST"
    end

    test "maps suspense to Liabilities root" do
      assert BeancountMapper.to_beancount_account(account("SUSPENSE:USD", "suspense")) ==
               "Liabilities:USD"
    end

    test "maps settlement to Assets root" do
      assert BeancountMapper.to_beancount_account(account("SETTLEMENT:USD", "settlement")) ==
               "Assets:USD"
    end

    test "maps clearing to Liabilities root" do
      assert BeancountMapper.to_beancount_account(account("CLEARING:USD", "clearing")) ==
               "Liabilities:USD"
    end

    test "maps tax to Liabilities root" do
      assert BeancountMapper.to_beancount_account(account("TAX:VAT", "tax")) ==
               "Liabilities:VAT"
    end

    test "CamelCases segments with underscores" do
      assert BeancountMapper.to_beancount_account(
               account("LIABILITIES:CLIENT_DEPOSITS", "liability")
             ) ==
               "Liabilities:CLIENTDEPOSITS"
    end
  end

  describe "to_beancount_opens/2" do
    test "creates open directives for a list of accounts" do
      accounts = [account("ASSETS:CASH", "asset"), account("LIABILITIES:DEPOSITS", "liability")]
      opens = BeancountMapper.to_beancount_opens(accounts, ~D[2026-01-01])
      assert length(opens) == 2
      assert hd(opens).__struct__ == Beancount.Directives.Open
    end
  end

  describe "to_beancount_posting/2" do
    test "creates a Beancount posting with signed amount" do
      posting = %Posting{
        account_code: "ASSETS:CASH",
        debit_credit: "debit",
        amount: Decimal.new("100"),
        currency: "USD"
      }

      account = account("ASSETS:CASH", "asset")
      bc_posting = BeancountMapper.to_beancount_posting(posting, account)
      assert bc_posting.__struct__ == Beancount.Directives.Posting
      assert bc_posting.account == "Assets:CASH"
    end
  end

  describe "to_beancount_directive/3" do
    test "creates a transaction directive with metadata" do
      journal = %Journal{
        id: 1,
        event_id: "evt_1",
        selected_policy: "cash_deposit",
        selected_template: "cash_deposit",
        description: "test",
        effective_date: ~D[2026-07-07]
      }

      postings = [
        %Posting{
          account_code: "ASSETS:CASH",
          debit_credit: "debit",
          amount: Decimal.new("100"),
          currency: "USD",
          sequence: 1
        },
        %Posting{
          account_code: "LIABILITIES:DEPOSITS",
          debit_credit: "credit",
          amount: Decimal.new("100"),
          currency: "USD",
          sequence: 2
        }
      ]

      accounts = %{
        "ASSETS:CASH" => account("ASSETS:CASH", "asset"),
        "LIABILITIES:DEPOSITS" => account("LIABILITIES:DEPOSITS", "liability")
      }

      directive = BeancountMapper.to_beancount_directive(journal, postings, accounts)
      assert directive.__struct__ == Beancount.Directives.Transaction
      assert directive.date == ~D[2026-07-07]
      assert directive.narration == "test"
      assert length(directive.postings) == 2
    end

    test "excludes nil metadata values" do
      journal = %Journal{
        id: 1,
        event_id: nil,
        selected_policy: nil,
        effective_date: ~D[2026-07-07],
        description: "d"
      }

      accounts = %{"A" => account("A", "asset")}

      postings = [
        %Posting{
          account_code: "A",
          debit_credit: "debit",
          amount: Decimal.new("1"),
          currency: "USD",
          sequence: 1
        }
      ]

      directive = BeancountMapper.to_beancount_directive(journal, postings, accounts)
      refute Map.has_key?(directive.metadata, "logistiki_event_id")
      refute Map.has_key?(directive.metadata, "logistiki_policy")
    end

    test "uses today when effective_date is nil" do
      journal = %Journal{id: 1, effective_date: nil, description: "d"}
      accounts = %{"A" => account("A", "asset")}

      postings = [
        %Posting{
          account_code: "A",
          debit_credit: "debit",
          amount: Decimal.new("1"),
          currency: "USD",
          sequence: 1
        }
      ]

      directive = BeancountMapper.to_beancount_directive(journal, postings, accounts)
      assert directive.date == Date.utc_today()
    end
  end

  describe "from_beancount_balance/1" do
    test "converts a query result to a map" do
      result = %Beancount.Query.Result{
        columns: ["account", "balance"],
        rows: [["Assets:Cash", "100.00 USD"], ["Liabilities:Deposits", "-100.00 USD"]]
      }

      balances = BeancountMapper.from_beancount_balance(result)
      assert balances["Assets:Cash"] == "100.00 USD"
      assert balances["Liabilities:Deposits"] == "-100.00 USD"
    end

    test "passes through error tuples" do
      assert BeancountMapper.from_beancount_balance({:error, :something}) == {:error, :something}
    end
  end

  describe "from_beancount_entry/1" do
    test "converts rows to maps" do
      result = %Beancount.Query.Result{
        columns: ["account", "balance"],
        rows: [["Assets:Cash", "100"]]
      }

      [entry] = BeancountMapper.from_beancount_entry(result)
      assert entry == %{"account" => "Assets:Cash", "balance" => "100"}
    end
  end

  describe "root_for_type/1" do
    test "returns the beancount root for each type" do
      assert BeancountMapper.root_for_type(:asset) == "Assets"
      assert BeancountMapper.root_for_type(:liability) == "Liabilities"
      assert BeancountMapper.root_for_type(:equity) == "Equity"
      assert BeancountMapper.root_for_type(:income) == "Income"
      assert BeancountMapper.root_for_type(:expense) == "Expenses"
    end
  end

  describe "normal_debit?/1" do
    test "true for asset" do
      assert BeancountMapper.normal_debit?(:asset)
    end

    test "true for expense" do
      assert BeancountMapper.normal_debit?(:expense)
    end

    test "true for settlement" do
      assert BeancountMapper.normal_debit?(:settlement)
    end

    test "false for liability" do
      refute BeancountMapper.normal_debit?(:liability)
    end

    test "false for income" do
      refute BeancountMapper.normal_debit?(:income)
    end
  end

  describe "signed_amount/2" do
    test "returns positive for debit" do
      posting = %Posting{debit_credit: "debit", amount: Decimal.new("100")}
      assert BeancountMapper.signed_amount(posting, account("A", "asset")) == Decimal.new("100")
    end

    test "returns negative for credit" do
      posting = %Posting{debit_credit: "credit", amount: Decimal.new("100")}

      assert BeancountMapper.signed_amount(posting, account("A", "liability")) ==
               Decimal.new("-100")
    end
  end
end
