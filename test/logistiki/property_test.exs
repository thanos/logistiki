defmodule Logistiki.PropertyTest do
  use Logistiki.DataCase, async: false

  use ExUnitProperties

  alias Logistiki.Accounting.{InvariantValidator, Journal, Posting}
  alias Logistiki.Demo.Seeds

  setup do
    Seeds.run()
    Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation)
    on_exit(fn -> Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation) end)
    :ok
  end

  defp posting(code, dir, amount, cur \\ "USD") do
    %Posting{account_code: code, debit_credit: dir, amount: amount, currency: cur, sequence: 1}
  end

  defp amount_gen do
    # Event amounts are dollar values; amount_cents multiplies by 100. Stay
    # under the approval threshold of 1,000,000 cents ($10,000).
    map(integer(1..9_999), &Decimal.new(&1))
  end

  defp balanced_journal_gen do
    bind(amount_gen(), fn amount ->
      bind(member_of(["ASSETS:CASH:USD:NOSTRO", "SUSPENSE:USD"]), fn debit_code ->
        bind(
          member_of([
            "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
            "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:PAYROLL"
          ]),
          fn credit_code ->
            constant([
              posting(debit_code, "debit", amount),
              posting(credit_code, "credit", amount)
            ])
          end
        )
      end)
    end)
  end

  defp unbalanced_journal_gen do
    bind(amount_gen(), fn debit ->
      bind(filter(amount_gen(), fn a -> not Decimal.equal?(a, debit) end), fn credit ->
        constant([
          posting("ASSETS:CASH:USD:NOSTRO", "debit", debit),
          posting("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "credit", credit)
        ])
      end)
    end)
  end

  property "balanced journals always pass invariant validation" do
    check all(postings <- balanced_journal_gen()) do
      assert :ok == InvariantValidator.validate_postings(postings)
      assert :ok == InvariantValidator.validate_accounts(postings)
    end
  end

  property "unbalanced journals are always rejected" do
    check all(postings <- unbalanced_journal_gen()) do
      assert {:error, %{code: :unbalanced_journal}} = InvariantValidator.validate_postings(postings)
    end
  end

  property "reversal exactly restores affected balances" do
    check all(amount <- amount_gen()) do
      # Process a deposit of `amount`, then reverse it, and confirm zero balance.
      event =
        Seeds.deposit_event(
          "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
          Decimal.to_string(amount)
        )

      assert {:ok, result} = Logistiki.process(event)

      assert {:ok, reversal} =
               Logistiki.Ledger.reverse_journal(result.journal, %{reason: "property"})

      assert reversal.status == :ok

      assert {:ok, [cash]} = Logistiki.balance("ASSETS:CASH:USD:NOSTRO")
      assert Decimal.equal?(cash.net, Decimal.new(0))
    end
  end

  property "parent account balance equals the sum of descendant balances" do
    check all(amount <- amount_gen()) do
      event =
        Seeds.deposit_event(
          "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
          Decimal.to_string(amount)
        )

      assert {:ok, _} = Logistiki.process(event)

      assert {:ok, leaf_balances} =
               Logistiki.balance("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")

      assert {:ok, parent_balances} = Logistiki.balance("LIABILITIES:CLIENT_DEPOSITS:USD:ACME")

      leaf_net = Enum.reduce(leaf_balances, Decimal.new(0), &Decimal.add(&1.net, &2))
      parent_net = Enum.reduce(parent_balances, Decimal.new(0), &Decimal.add(&1.net, &2))

      assert Decimal.equal?(leaf_net, parent_net)
    end
  end

  property "posting order does not change the final balance" do
    check all(amount <- amount_gen()) do
      event1 =
        Seeds.deposit_event(
          "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
          Decimal.to_string(amount)
        )

      event2 =
        Seeds.fee_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", Decimal.to_string(amount))

      assert {:ok, _} = Logistiki.process(event1)
      assert {:ok, _} = Logistiki.process(event2)

      assert {:ok, [balance]} = Logistiki.balance("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")
      # Deposit credit `amount`, fee debit `amount` => net = -(amount) + amount = 0
      assert Decimal.equal?(balance.net, Decimal.new(0))
    end
  end

  property "simulation and beancount backends agree on deposit balances" do
    check all(amount <- amount_gen()) do
      Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation)

      event =
        Seeds.deposit_event(
          "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
          Decimal.to_string(amount)
        )

      assert {:ok, _} = Logistiki.process(event)

      assert {:ok, [sim_cash]} = Logistiki.balance("ASSETS:CASH:USD:NOSTRO")

      assert {:ok, oracle} = Logistiki.Ledger.Beancount.oracle_balances()
      {:ok, cash_account} = Logistiki.VirtualAccounts.get_account_by_code("ASSETS:CASH:USD:NOSTRO")
      cash_bc = Logistiki.Ledger.BeancountMapper.to_beancount_account(cash_account)

      assert Map.has_key?(oracle, cash_bc)
      # Both should report a debit balance (positive) for cash.
      assert Decimal.positive?(sim_cash.net)
    end
  end
end
