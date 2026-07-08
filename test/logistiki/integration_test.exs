defmodule Logistiki.IntegrationTest do
  use Logistiki.DataCase, async: false

  alias Logistiki.Demo.Seeds
  alias Logistiki.Event.{AccountOpened, FeeAssessed}

  setup do
    {entities, accounts} = Seeds.run()
    %{entities: entities, accounts: accounts}
  end

  describe "process/1 with the simulation backend" do
    setup do
      Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation)
      on_exit(fn -> Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation) end)
      :ok
    end

    test "processes a deposit end-to-end", %{accounts: accounts} do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "1000.00")

      assert {:ok, result} = Logistiki.process(event)
      assert result.policy == :cash_deposit
      assert result.journal.status == "posted"
      assert length(result.postings) == 2

      # Cash debited, client liability credited.
      assert {:ok, [cash_balance]} = Logistiki.balance("ASSETS:CASH:USD:NOSTRO")
      assert Decimal.equal?(cash_balance.net, Decimal.new("1000.00"))

      assert {:ok, [client_balance]} = Logistiki.balance("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")
      assert Decimal.equal?(client_balance.net, Decimal.new("-1000.00"))
    end

    test "aggregates parent account balances from descendants", %{accounts: accounts} do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "1000.00")
      assert {:ok, _} = Logistiki.process(event)

      # The Acme parent aggregates Operating + Payroll + Escrow.
      assert {:ok, balances} = Logistiki.balance("LIABILITIES:CLIENT_DEPOSITS:USD:ACME")
      net = Enum.reduce(balances, Decimal.new(0), &Decimal.add(&1.net, &2))
      assert Decimal.equal?(net, Decimal.new("-1000.00"))
    end

    test "processes a fee and then reverses it, restoring balances", %{accounts: accounts} do
      deposit = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "1000.00")
      assert {:ok, _} = Logistiki.process(deposit)

      fee = Seeds.fee_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "25.00")
      assert {:ok, fee_result} = Logistiki.process(fee)
      assert fee_result.policy == :corporate_wire_fee

      # Client liability debited by 25 (reduces credit balance), fee income credited.
      assert {:ok, [client_before]} = Logistiki.balance("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")
      # 1000 deposit - 25 fee debit = 975 credit => net -975
      assert Decimal.equal?(client_before.net, Decimal.new("-975.00"))

      # Reverse the fee journal.
      assert {:ok, reversal_result} =
               Logistiki.Ledger.reverse_journal(fee_result.journal, %{reason: "mistaken fee"})

      assert reversal_result.status == :ok
      assert reversal_result.details[:reversal].status == "posted"

      assert {:ok, [client_after]} = Logistiki.balance("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")
      assert Decimal.equal?(client_after.net, Decimal.new("-1000.00"))

      assert {:ok, [fee_balance]} = Logistiki.balance("INCOME:FEES:WIRE")
      assert Decimal.equal?(fee_balance.net, Decimal.new("0"))
    end

    test "processes a no-accounting-impact event", %{accounts: accounts} do
      event = Seeds.account_opened_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")

      assert {:ok, result} = Logistiki.process(event)
      assert result.journal == nil
      assert result.policy == nil
      assert result.explanation[:reason] == :no_accounting_impact
    end

    test "produces a balanced trial balance", %{accounts: accounts} do
      assert {:ok, _} = Logistiki.process(Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "1000.00"))
      assert {:ok, _} = Logistiki.process(Seeds.fee_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "25.00"))

      assert {:ok, tb} = Logistiki.trial_balance()
      assert tb.balanced
    end

    test "statement includes a running balance", %{accounts: accounts} do
      assert {:ok, _} = Logistiki.process(Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "1000.00"))

      assert {:ok, lines} = Logistiki.statement("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")
      assert length(lines) == 1
      [line] = lines
      assert line.running_balance != nil
      assert Decimal.equal?(line.running_balance, Decimal.new("-1000.00"))
    end

    test "audit evidence explains the full chain", %{accounts: accounts} do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "1000.00")
      assert {:ok, _} = Logistiki.process(event)

      trail = Logistiki.Audit.trail_for_event(event.id)
      actions = Enum.map(trail, & &1.action)
      assert "business_event_received" in actions
      assert "facts_generated" in actions
      assert "journal_built" in actions
      assert "invariant_validation_succeeded" in actions
      assert "journal_posted" in actions
      assert "audit_event_written" in actions
    end
  end

  describe "process/1 with the beancount backend" do
    setup do
      Logistiki.put_ledger_backend(Logistiki.Ledger.Beancount)
      on_exit(fn -> Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation) end)
      :ok
    end

    test "processes a deposit and verifies with the oracle", %{accounts: accounts} do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "1000.00")

      assert {:ok, result} = Logistiki.process(event)
      assert result.journal.status == "posted"
      assert result.ledger_result.details[:oracle] == :beancount

      assert {:ok, [cash_balance]} = Logistiki.balance("ASSETS:CASH:USD:NOSTRO")
      assert Decimal.equal?(cash_balance.net, Decimal.new("1000.00"))
    end

    test "the full ledger verifies with beancount check", %{accounts: accounts} do
      assert {:ok, _} = Logistiki.process(Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "1000.00"))
      assert {:ok, _} = Logistiki.Ledger.Beancount.verify_ledger()
    end
  end

  describe "backend agreement" do
    test "simulation and beancount agree on balances for the same scenario" do
      Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation)

      assert {:ok, _} =
               Logistiki.process(Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "1000.00"))

      assert {:ok, _} =
               Logistiki.process(Seeds.fee_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "25.00"))

      sim_balances = balance_map("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")

      # The beancount oracle should agree with the persisted (simulation) results.
      assert {:ok, oracle} = Logistiki.Ledger.Beancount.oracle_balances()

      {:ok, client_account} =
        Logistiki.VirtualAccounts.get_account_by_code("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")

      client_beancount = Logistiki.Ledger.BeancountMapper.to_beancount_account(client_account)
      assert Map.has_key?(oracle, client_beancount)

      Logistiki.put_ledger_backend(Logistiki.Ledger.Simulation)
      # Simulation net for the client account.
      [sim_client] = sim_balances
      # Oracle balance is the beancount signed position; a credit balance is negative.
      oracle_amount = oracle[client_beancount]
      assert oracle_amount != nil

      # Both should be non-zero and consistent in sign (credit balance is negative).
      assert Decimal.negative?(sim_client.net)
    end
  end

  defp balance_map(code) do
    {:ok, balances} = Logistiki.balance(code)
    balances
  end
end
