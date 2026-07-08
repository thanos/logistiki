defmodule Logistiki.Knowledge.TemplateResolverTest do
  use Logistiki.DataCase, async: true

  alias Logistiki.Event.Normalized
  alias Logistiki.Knowledge.TemplateResolver

  describe "resolve/1" do
    test "resolves template postings for a deposit" do
      event =
        Normalized.new(%{
          type: "deposit_received",
          amount: Decimal.new("1000.00"),
          currency: "USD",
          account_code: "LIAB:ACME",
          cash_account_code: "ASSETS:CASH"
        })

      assert {:ok, result, postings} = TemplateResolver.resolve(event)
      assert result.policy == :cash_deposit
      assert length(postings) == 2
      assert hd(postings).role == :cash_account
    end

    test "returns :no_template_found for unknown event" do
      event = Normalized.new(%{type: "mystery", amount: Decimal.new("1.00")})
      assert {:error, :no_template_found} = TemplateResolver.resolve(event)
    end
  end

  describe "resolve_account_role/2" do
    test "resolves an existing role" do
      roles = %{cash_account: "ASSETS:CASH:USD:NOSTRO"}

      assert {:ok, "ASSETS:CASH:USD:NOSTRO"} =
               TemplateResolver.resolve_account_role(roles, :cash_account)
    end

    test "returns error for a missing role" do
      assert {:error, {:missing_account_role, :unknown}} =
               TemplateResolver.resolve_account_role(%{}, :unknown)
    end
  end
end
