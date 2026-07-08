defmodule Logistiki.Knowledge.RulesTest do
  use ExUnit.Case, async: true

  alias Logistiki.Knowledge.Rules

  describe "categories/0" do
    test "returns three rule categories" do
      categories = Rules.categories()
      assert Keyword.get(categories, :business_rules)
      assert Keyword.get(categories, :accounting_policies)
      assert Keyword.get(categories, :ledger_invariants)
    end

    test "describes business rules as Datalog-backed" do
      categories = Rules.categories()
      assert String.contains?(categories[:business_rules], "Datalog")
    end

    test "describes ledger invariants as pure Elixir" do
      categories = Rules.categories()
      assert String.contains?(categories[:ledger_invariants], "Elixir")
    end
  end
end
