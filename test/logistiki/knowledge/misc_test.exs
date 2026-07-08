defmodule Logistiki.Knowledge.MiscTest do
  use Logistiki.DataCase, async: true

  alias Logistiki.Knowledge
  alias Logistiki.Event.Normalized

  describe "load_program/0" do
    test "returns the configured program module" do
      assert Knowledge.load_program() == Logistiki.Knowledge.Program
    end
  end

  describe "evaluate/2" do
    test "evaluates a deposit event" do
      event =
        Normalized.new(%{
          type: "deposit_received",
          amount: Decimal.new("1000.00"),
          currency: "USD",
          account_code: "LIAB:ACME",
          cash_account_code: "ASSETS:CASH"
        })

      assert {:ok, result} = Knowledge.evaluate(event)
      assert result.policy == :cash_deposit
    end
  end

  describe "materialize/2" do
    test "returns raw ExDatalog knowledge" do
      event =
        Normalized.new(%{
          type: "deposit_received",
          amount: Decimal.new("1000.00"),
          currency: "USD",
          account_code: "LIAB:ACME",
          cash_account_code: "ASSETS:CASH"
        })

      assert {:ok, knowledge} = Knowledge.materialize(event)
      assert :cash_deposit in Logistiki.Knowledge.KnowledgeBase.derived_policies(knowledge)
    end
  end

  describe "assert_fact/2" do
    test "returns the fact tuple" do
      assert Knowledge.assert_fact(:event_type, [:evt, :deposit_received]) ==
               {:event_type, [:evt, :deposit_received]}
    end

    test "requires atom predicate" do
      assert_raise FunctionClauseError, fn ->
        Knowledge.assert_fact("event_type", [:evt])
      end
    end

    test "requires list arguments" do
      assert_raise FunctionClauseError, fn ->
        Knowledge.assert_fact(:event_type, :not_a_list)
      end
    end
  end

  describe "rule_categories/0" do
    test "returns the rule categories" do
      cats = Knowledge.rule_categories()
      assert Keyword.get(cats, :business_rules)
      assert Keyword.get(cats, :accounting_policies)
      assert Keyword.get(cats, :ledger_invariants)
    end
  end

  describe "KnowledgeBase.raw_knowledge/2" do
    test "returns materialized knowledge" do
      event = Normalized.new(%{type: "deposit_received", amount: Decimal.new("1.00")})
      assert {:ok, _} = Logistiki.Knowledge.KnowledgeBase.raw_knowledge(event)
    end

    test "derived_account_roles returns role map" do
      event =
        Normalized.new(%{
          type: "deposit_received",
          amount: Decimal.new("1.00"),
          currency: "USD",
          account_code: "LIAB:ACME",
          cash_account_code: "ASSETS:CASH"
        })

      {:ok, knowledge} = Logistiki.Knowledge.KnowledgeBase.raw_knowledge(event)
      roles = Logistiki.Knowledge.KnowledgeBase.derived_account_roles(knowledge)
      assert roles[:client_liability_account] == "LIAB:ACME"
      assert roles[:cash_account] == "ASSETS:CASH"
    end
  end
end
