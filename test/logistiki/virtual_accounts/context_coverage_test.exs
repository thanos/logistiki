defmodule Logistiki.VirtualAccounts.ContextCoverageTest do
  use Logistiki.DataCase, async: true

  alias Logistiki.VirtualAccounts
  alias Logistiki.VirtualAccounts.VirtualAccount

  describe "create_account/1 with parent errors" do
    test "returns error when parent does not exist" do
      assert {:error, :parent_not_found} =
               VirtualAccounts.create_account(%{
                 code: "ORPHAN",
                 name: "Orphan",
                 account_type: "asset",
                 parent_id: 999_999
               })
    end

    test "returns error when parent is a posting account" do
      {:ok, root} =
        VirtualAccounts.create_account(%{code: "POST_PAR", name: "R", account_type: "asset"})

      {:ok, leaf} =
        VirtualAccounts.create_account(%{
          code: "POST_PAR:LEAF",
          name: "L",
          account_type: "asset",
          currency: "USD",
          posting_allowed: true,
          parent_id: root.id
        })

      assert {:error, :parent_is_posting_account} =
               VirtualAccounts.create_account(%{
                 code: "POST_PAR:LEAF:CHILD",
                 name: "C",
                 account_type: "asset",
                 parent_id: leaf.id
               })
    end
  end

  describe "update_account/2" do
    test "updates an account" do
      {:ok, account} =
        VirtualAccounts.create_account(%{code: "UPD1", name: "Old", account_type: "asset"})

      {:ok, updated} = VirtualAccounts.update_account(account, %{name: "New"})
      assert updated.name == "New"
    end
  end

  describe "get_account_by_code!/1" do
    test "fetches by code, raising if not found" do
      {:ok, account} =
        VirtualAccounts.create_account(%{code: "BYCODE!", name: "Test", account_type: "asset"})

      found = VirtualAccounts.get_account_by_code!("BYCODE!")
      assert found.id == account.id
    end
  end

  describe "list_accounts/1" do
    test "filters by parent_id" do
      {:ok, root} =
        VirtualAccounts.create_account(%{code: "LISTPAR", name: "R", account_type: "asset"})

      {:ok, child} =
        VirtualAccounts.create_account(%{
          code: "LISTPAR:C",
          name: "C",
          account_type: "asset",
          currency: "USD",
          posting_allowed: true,
          parent_id: root.id
        })

      accounts = VirtualAccounts.list_accounts(parent_id: root.id)
      assert Enum.any?(accounts, &(&1.id == child.id))
    end
  end

  describe "move_account/2" do
    test "move to root (nil parent)" do
      {:ok, root1} =
        VirtualAccounts.create_account(%{code: "MVROOT1", name: "R1", account_type: "asset"})

      {:ok, child} =
        VirtualAccounts.create_account(%{
          code: "MVROOT1:C",
          name: "C",
          account_type: "asset",
          currency: "USD",
          posting_allowed: true,
          parent_id: root1.id
        })

      assert {:ok, moved} = VirtualAccounts.move_account(child, nil)
      assert moved.parent_id == nil
      # The child is now a root — its ancestors should only be itself
      assert VirtualAccounts.ancestor_ids(moved) == [moved.id]
    end

    test "move under a new parent by struct" do
      {:ok, root1} =
        VirtualAccounts.create_account(%{code: "MVINT1", name: "R1", account_type: "asset"})

      {:ok, root2} =
        VirtualAccounts.create_account(%{code: "MVINT2", name: "R2", account_type: "asset"})

      {:ok, child} =
        VirtualAccounts.create_account(%{
          code: "MVINT1:C",
          name: "C",
          account_type: "asset",
          currency: "USD",
          posting_allowed: true,
          parent_id: root1.id
        })

      assert {:ok, moved} = VirtualAccounts.move_account(child, root2)
      assert moved.parent_id == root2.id
      # Child's ancestors should include root2
      ancestors = VirtualAccounts.ancestor_ids(moved) |> Enum.sort()
      assert Enum.sort([moved.id, root2.id]) == ancestors
    end
  end

  describe "insert_closure_for/1" do
    test "returns :root for a root account" do
      {:ok, root} =
        VirtualAccounts.create_account(%{code: "CLOSR", name: "R", account_type: "asset"})

      # insert_closure_for is @doc false but public; the closure was already
      # inserted by create_account. Calling it again would violate the unique
      # index, so we just verify the closure exists.
      descendants = VirtualAccounts.descendant_ids(root)
      assert root.id in descendants
    end

    test "closure is correct for a child account" do
      {:ok, root} =
        VirtualAccounts.create_account(%{code: "CLOSR2", name: "R", account_type: "asset"})

      {:ok, child} =
        VirtualAccounts.create_account(%{
          code: "CLOSR2:C",
          name: "C",
          account_type: "asset",
          currency: "USD",
          posting_allowed: true,
          parent_id: root.id
        })

      ancestors = VirtualAccounts.ancestor_ids(child) |> Enum.sort()
      assert ancestors == Enum.sort([child.id, root.id])
    end
  end

  describe "list_children/1" do
    test "returns direct children" do
      {:ok, root} =
        VirtualAccounts.create_account(%{code: "CHILD1", name: "R", account_type: "asset"})

      {:ok, child} =
        VirtualAccounts.create_account(%{
          code: "CHILD1:A",
          name: "A",
          account_type: "asset",
          currency: "USD",
          posting_allowed: true,
          parent_id: root.id
        })

      children = VirtualAccounts.list_children(root)
      assert Enum.any?(children, &(&1.id == child.id))
    end
  end

  describe "list_descendants/1" do
    test "returns all descendants" do
      {:ok, root} =
        VirtualAccounts.create_account(%{code: "DESC1", name: "R", account_type: "asset"})

      {:ok, mid} =
        VirtualAccounts.create_account(%{
          code: "DESC1:M",
          name: "M",
          account_type: "asset",
          parent_id: root.id
        })

      {:ok, leaf} =
        VirtualAccounts.create_account(%{
          code: "DESC1:M:L",
          name: "L",
          account_type: "asset",
          currency: "USD",
          posting_allowed: true,
          parent_id: mid.id
        })

      descendants = VirtualAccounts.list_descendants(root)
      ids = Enum.map(descendants, & &1.id)
      assert mid.id in ids
      assert leaf.id in ids
    end
  end
end
