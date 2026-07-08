defmodule Logistiki.VirtualAccountsTest do
  use Logistiki.DataCase, async: true

  alias Logistiki.VirtualAccounts

  describe "create_account/1" do
    test "creates an aggregation root with nil currency" do
      assert {:ok, root} =
               VirtualAccounts.create_account(%{
                 code: "ASSETS",
                 name: "Assets",
                 account_type: "asset",
                 normal_balance: "debit"
               })

      assert root.parent_id == nil
      assert root.currency == nil
      assert root.posting_allowed == false
      assert VirtualAccounts.ancestor_ids(root) == [root.id]
    end

    test "creates a leaf posting account that requires currency" do
      {:ok, root} =
        VirtualAccounts.create_account(%{code: "ASSETS", name: "Assets", account_type: "asset"})

      assert {:ok, leaf} =
               VirtualAccounts.create_account(%{
                 code: "ASSETS:CASH:USD:NOSTRO",
                 name: "Nostro USD",
                 account_type: "asset",
                 currency: "USD",
                 posting_allowed: true,
                 normal_balance: "debit",
                 parent_id: root.id
               })

      assert VirtualAccounts.leaf?(leaf)
      assert VirtualAccounts.posting_account?(leaf)
    end

    test "rejects posting account without currency" do
      {:ok, root} =
        VirtualAccounts.create_account(%{code: "ASSETS", name: "Assets", account_type: "asset"})

      assert {:error, changeset} =
               VirtualAccounts.create_account(%{
                 code: "ASSETS:CASH",
                 name: "Cash",
                 account_type: "asset",
                 posting_allowed: true,
                 parent_id: root.id
               })

      assert %{currency: _} = errors_on(changeset)
    end

    test "rejects duplicate code" do
      assert {:ok, _} =
               VirtualAccounts.create_account(%{
                 code: "ASSETS",
                 name: "Assets",
                 account_type: "asset"
               })

      assert {:error, changeset} =
               VirtualAccounts.create_account(%{
                 code: "ASSETS",
                 name: "Other",
                 account_type: "asset"
               })

      assert %{code: _} = errors_on(changeset)
    end
  end

  describe "move_account/2" do
    test "prevents cycles" do
      {:ok, a} = VirtualAccounts.create_account(%{code: "A", name: "A", account_type: "asset"})

      {:ok, b} =
        VirtualAccounts.create_account(%{
          code: "B",
          name: "B",
          account_type: "asset",
          parent_id: a.id
        })

      assert {:error, :cycle_detected} = VirtualAccounts.move_account(a, b)
    end

    test "moves an account under a new root" do
      {:ok, a} = VirtualAccounts.create_account(%{code: "A", name: "A", account_type: "asset"})

      {:ok, b} =
        VirtualAccounts.create_account(%{
          code: "B",
          name: "B",
          account_type: "asset",
          parent_id: a.id
        })

      {:ok, c} = VirtualAccounts.create_account(%{code: "C", name: "C", account_type: "asset"})

      assert {:ok, moved} = VirtualAccounts.move_account(b, c)
      assert moved.parent_id == c.id
      assert b.id in VirtualAccounts.descendant_ids(c)
    end
  end

  describe "get_account_by_code/1" do
    test "resolves by code" do
      {:ok, _} =
        VirtualAccounts.create_account(%{code: "ASSETS", name: "Assets", account_type: "asset"})

      assert {:ok, found} = VirtualAccounts.get_account_by_code("ASSETS")
      assert found.code == "ASSETS"
    end
  end
end
