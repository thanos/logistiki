defmodule Logistiki.VirtualAccounts.MiscTest do
  use Logistiki.DataCase, async: true

  alias Logistiki.VirtualAccounts
  alias Logistiki.VirtualAccounts.VirtualAccount

  describe "VirtualAccount enum functions" do
    test "account_types/0 returns all types" do
      types = VirtualAccount.account_types()

      for t <- [
            :asset,
            :liability,
            :equity,
            :income,
            :expense,
            :client,
            :settlement,
            :suspense,
            :fee,
            :tax,
            :clearing
          ] do
        assert t in types
      end
    end

    test "normal_balances/0 returns debit and credit" do
      balances = VirtualAccount.normal_balances()
      assert :debit in balances
      assert :credit in balances
    end

    test "statuses/0 returns all statuses" do
      statuses = VirtualAccount.statuses()

      for s <- [:active, :inactive, :frozen, :closed] do
        assert s in statuses
      end
    end
  end

  describe "leaf?/1" do
    test "true for an account with no children" do
      {:ok, root} =
        VirtualAccounts.create_account(%{code: "LEAF_ROOT", name: "Root", account_type: "asset"})

      {:ok, leaf} =
        VirtualAccounts.create_account(%{
          code: "LEAF_ROOT:CHILD",
          name: "Child",
          account_type: "asset",
          currency: "USD",
          posting_allowed: true,
          parent_id: root.id
        })

      assert VirtualAccounts.leaf?(leaf)
    end

    test "false for an account with children" do
      {:ok, root} =
        VirtualAccounts.create_account(%{code: "LEAF_ROOT2", name: "Root", account_type: "asset"})

      VirtualAccounts.create_account(%{
        code: "LEAF_ROOT2:CHILD",
        name: "Child",
        account_type: "asset",
        currency: "USD",
        posting_allowed: true,
        parent_id: root.id
      })

      refute VirtualAccounts.leaf?(root)
    end
  end

  describe "posting_account?/1" do
    test "true for an active posting-allowed account" do
      account = %VirtualAccount{posting_allowed: true, status: "active"}
      assert VirtualAccounts.posting_account?(account)
    end

    test "false for a frozen posting-allowed account" do
      account = %VirtualAccount{posting_allowed: true, status: "frozen"}
      refute VirtualAccounts.posting_account?(account)
    end

    test "false for an active non-posting account" do
      account = %VirtualAccount{posting_allowed: false, status: "active"}
      refute VirtualAccounts.posting_account?(account)
    end
  end

  describe "resolve/1" do
    test "resolves a struct directly" do
      {:ok, account} =
        VirtualAccounts.create_account(%{code: "RESOLVE1", name: "Test", account_type: "asset"})

      assert {:ok, ^account} = VirtualAccounts.resolve(account)
    end

    test "resolves by code" do
      {:ok, account} =
        VirtualAccounts.create_account(%{code: "RESOLVE2", name: "Test", account_type: "asset"})

      assert {:ok, ^account} = VirtualAccounts.resolve("RESOLVE2")
    end

    test "resolves by numeric id string" do
      {:ok, account} =
        VirtualAccounts.create_account(%{code: "RESOLVE3", name: "Test", account_type: "asset"})

      assert {:ok, ^account} = VirtualAccounts.resolve(Integer.to_string(account.id))
    end

    test "returns error for unknown code" do
      assert {:error, :not_found} = VirtualAccounts.resolve("NONEXISTENT_CODE")
    end

    test "returns error for unknown numeric id" do
      assert {:error, :not_found} = VirtualAccounts.resolve("999999")
    end
  end

  describe "get_account/1" do
    test "returns {:ok, account} when found" do
      {:ok, account} =
        VirtualAccounts.create_account(%{code: "GET1", name: "Test", account_type: "asset"})

      assert {:ok, ^account} = VirtualAccounts.get_account(account.id)
    end

    test "returns {:error, :not_found} when not found" do
      assert {:error, :not_found} = VirtualAccounts.get_account(999_999)
    end
  end

  describe "list_ancestors/1" do
    test "lists ancestors ordered by depth" do
      {:ok, root} =
        VirtualAccounts.create_account(%{code: "ANC_ROOT", name: "Root", account_type: "asset"})

      {:ok, mid} =
        VirtualAccounts.create_account(%{
          code: "ANC_ROOT:MID",
          name: "Mid",
          account_type: "asset",
          parent_id: root.id
        })

      {:ok, leaf} =
        VirtualAccounts.create_account(%{
          code: "ANC_ROOT:MID:LEAF",
          name: "Leaf",
          account_type: "asset",
          currency: "USD",
          posting_allowed: true,
          parent_id: mid.id
        })

      ancestors = VirtualAccounts.list_ancestors(leaf)
      assert length(ancestors) == 2
      assert hd(ancestors).id == mid.id
      assert List.last(ancestors).id == root.id
    end

    test "returns empty list for a root" do
      {:ok, root} =
        VirtualAccounts.create_account(%{code: "ANC_ROOT2", name: "Root", account_type: "asset"})

      assert VirtualAccounts.list_ancestors(root) == []
    end
  end
end
