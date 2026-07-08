defmodule Logistiki.KnowledgeTest do
  use Logistiki.DataCase, async: true

  alias Logistiki.Event.Normalized
  alias Logistiki.Knowledge
  alias Logistiki.Knowledge.KnowledgeBase

  defp deposit_event do
    Normalized.new(%{
      id: "evt_1",
      type: "deposit_received",
      amount: Decimal.new("1000.00"),
      currency: "USD",
      account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
      cash_account_code: "ASSETS:CASH:USD:NOSTRO",
      entity_type: "corporate",
      effective_date: ~D[2026-07-07]
    })
  end

  defp fee_event(fee_type, entity_type) do
    Normalized.new(%{
      id: "evt_2",
      type: "fee_assessed",
      amount: Decimal.new("25.00"),
      currency: "USD",
      account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
      fee_income_account_code: "INCOME:FEES:WIRE",
      fee_type: fee_type,
      entity_type: entity_type
    })
  end

  describe "evaluate/1" do
    test "selects the cash_deposit policy for a deposit" do
      assert {:ok, result} = Knowledge.evaluate(deposit_event())
      assert result.policy == :cash_deposit
      assert result.template == :cash_deposit
      refute result.blocked
      refute result.requires_approval

      roles = result.account_roles
      assert roles[:cash_account] == "ASSETS:CASH:USD:NOSTRO"
      assert roles[:client_liability_account] == "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING"
    end

    test "selects corporate_wire_fee for a corporate wire fee" do
      assert {:ok, result} = Knowledge.evaluate(fee_event("wire_fee", "corporate"))
      assert result.policy == :corporate_wire_fee
      assert roles = result.account_roles
      assert roles[:fee_income_account] == "INCOME:FEES:WIRE"
    end

    test "selects retail_wire_fee for an individual wire fee" do
      assert {:ok, result} = Knowledge.evaluate(fee_event("wire_fee", "individual"))
      assert result.policy == :retail_wire_fee
    end

    test "returns no policy for an unknown event type" do
      event = Normalized.new(%{id: "evt_x", type: "mystery_event", amount: Decimal.new("1.00")})

      assert {:ok, result} = Knowledge.evaluate(event)
      assert result.policy == nil
      assert result.template_postings == []
    end

    test "requires_approval fires above the threshold" do
      %Normalized{} = base = deposit_event()
      event = %{base | amount: Decimal.new("100000.00")}

      assert {:ok, result} = Knowledge.evaluate(event)
      assert result.requires_approval
    end

    test "template postings are sorted by sequence" do
      assert {:ok, result} = Knowledge.evaluate(deposit_event())
      seqs = Enum.map(result.template_postings, & &1.sequence)
      assert seqs == [1, 2]

      [first, second] = result.template_postings
      assert first.direction == :debit
      assert first.role == :cash_account
      assert second.direction == :credit
      assert second.role == :client_liability_account
    end

    test "static account-role fallback resolves interest_expense_account" do
      event =
        Normalized.new(%{
          id: "evt_3",
          type: "interest_accrued",
          amount: Decimal.new("5.00"),
          currency: "USD",
          account_code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING",
          entity_type: "corporate"
        })

      assert {:ok, result} = Knowledge.evaluate(event)
      assert result.policy == :interest_accrual
      assert result.account_roles[:interest_expense_account] == "EXPENSES:INTEREST"
    end

    test "raw knowledge exposes derived policy facts" do
      assert {:ok, knowledge} = Knowledge.materialize(deposit_event())
      assert :cash_deposit in KnowledgeBase.derived_policies(knowledge)
    end
  end
end
