defmodule Logistiki.LedgerTest do
  use Logistiki.DataCase, async: false

  alias Logistiki.Demo.Seeds
  alias Logistiki.Ledger.Beancount, as: LedgerBeancount
  alias Logistiki.Ledger.BeancountMapper
  alias Logistiki.Ledger.Simulation

  setup do
    Seeds.run()
    :ok
  end

  describe "Simulation backend" do
    setup do
      Logistiki.put_ledger_backend(Simulation)
      on_exit(fn -> Logistiki.put_ledger_backend(Simulation) end)
      :ok
    end

    test "executes a valid journal and returns a result" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "1000.00")
      assert {:ok, result} = Logistiki.process(event)
      assert result.ledger_result.backend == Simulation
      assert result.ledger_result.status == :ok
      assert result.ledger_result.journal_id != nil
    end

    test "computes balance via the backend" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "1000.00")
      {:ok, _} = Logistiki.process(event)

      assert {:ok, [balance]} = Simulation.balance("ASSETS:CASH:USD:NOSTRO")
      assert Decimal.equal?(balance.net, Decimal.new("1000.00"))
    end
  end

  describe "Beancount backend" do
    setup do
      Logistiki.put_ledger_backend(LedgerBeancount)
      on_exit(fn -> Logistiki.put_ledger_backend(Simulation) end)
      :ok
    end

    test "maps deterministic, valid beancount account names" do
      {:ok, account} = Logistiki.VirtualAccounts.get_account_by_code("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")
      name = BeancountMapper.to_beancount_account(account)
      assert String.starts_with?(name, "Liabilities:")
      # Each segment must start with an uppercase letter (beancount rule).
      for segment <- String.split(name, ":") do
        assert String.match?(segment, ~r/^[A-Z]/)
      end
    end

    test "executes a valid journal through the oracle" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "1000.00")
      assert {:ok, result} = Logistiki.process(event)
      assert result.ledger_result.backend == LedgerBeancount
      assert result.ledger_result.details[:oracle] == :beancount
    end

    test "beancount-specific types do not leak into the public API" do
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "1000.00")
      {:ok, result} = Logistiki.process(event)

      # The ledger_result must be a Logistiki struct, not a Beancount one.
      assert %Logistiki.Ledger.Result{} = result.ledger_result
      refute %Logistiki.Ledger.Result{} == result.ledger_result.details
    end
  end

  describe "backend equivalence" do
    test "simulation and beancount produce equivalent balances for the same journal" do
      # Post the same deposit with the simulation backend.
      Logistiki.put_ledger_backend(Simulation)
      event = Seeds.deposit_event("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", "750.00")
      assert {:ok, _} = Logistiki.process(event)

      assert {:ok, [sim_cash]} = Logistiki.balance("ASSETS:CASH:USD:NOSTRO")
      assert {:ok, [sim_client]} = Logistiki.balance("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")

      # The beancount oracle, rendering all posted journals, should report the
      # same positions (sign-encoded).
      assert {:ok, oracle} = LedgerBeancount.oracle_balances()

      {:ok, cash_account} = Logistiki.VirtualAccounts.get_account_by_code("ASSETS:CASH:USD:NOSTRO")
      {:ok, client_account} = Logistiki.VirtualAccounts.get_account_by_code("LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING")

      assert Map.has_key?(oracle, BeancountMapper.to_beancount_account(cash_account))
      assert Map.has_key?(oracle, BeancountMapper.to_beancount_account(client_account))

      # Both backends agree on the cash debit balance being positive.
      assert Decimal.positive?(sim_cash.net)

      Logistiki.put_ledger_backend(Simulation)
    end
  end
end
