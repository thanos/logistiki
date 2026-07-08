defmodule Logistiki.RelationshipsTest do
  use Logistiki.DataCase, async: true

  alias Logistiki.BusinessEntities
  alias Logistiki.Relationships
  alias Logistiki.VirtualAccounts

  setup do
    {:ok, entity} = BusinessEntities.create_entity(%{name: "Acme", entity_type: "company"})

    {:ok, child_entity} =
      BusinessEntities.create_entity(%{
        name: "Acme Trading",
        entity_type: "company",
        parent_id: entity.id
      })

    {:ok, root} =
      VirtualAccounts.create_account(%{
        code: "LIAB",
        name: "Liabilities",
        account_type: "liability"
      })

    {:ok, account} =
      VirtualAccounts.create_account(%{
        code: "LIAB:ACME",
        name: "Acme",
        account_type: "client",
        currency: "USD",
        posting_allowed: true,
        parent_id: root.id
      })

    %{entity: entity, child_entity: child_entity, account: account, root: root}
  end

  test "links an entity to an account and lists it back", %{entity: entity, account: account} do
    assert {:ok, link} = Relationships.link_entity_account(entity, account, :owner)
    assert link.relationship_type == "owner"

    assert [listed] = Relationships.list_accounts_for_entity(entity)
    assert listed.id == account.id

    assert [listed_entity] = Relationships.list_entities_for_account(account)
    assert listed_entity.id == entity.id
  end

  test "allows multiple relationship types between the same pair", %{
    entity: entity,
    account: account
  } do
    assert {:ok, _} = Relationships.link_entity_account(entity, account, :owner)
    assert {:ok, _} = Relationships.link_entity_account(entity, account, :beneficiary)

    types =
      Relationships.list_accounts_for_entity(entity)
      |> Enum.count()

    # account appears once per relationship (joined on account, so distinct accounts)
    # but list_accounts_for_entity returns accounts; both rows point to same account.
    assert types == 2
  end

  test "lists accounts for an entity subtree", %{
    entity: entity,
    child_entity: child,
    account: account
  } do
    assert {:ok, _} = Relationships.link_entity_account(child, account, :owner)
    assert [listed] = Relationships.list_accounts_for_entity_tree(entity)
    assert listed.id == account.id
  end

  test "unlinks by setting valid_to", %{entity: entity, account: account} do
    assert {:ok, _} = Relationships.link_entity_account(entity, account, :owner)
    assert Relationships.unlink_entity_account(entity, account, :owner) == {1, nil}

    assert Relationships.list_accounts_for_entity(entity) == []
    assert [_] = Relationships.list_accounts_for_entity(entity, at: Date.utc_today())
  end

  test "rejects unknown relationship type", %{entity: entity, account: account} do
    assert {:error, changeset} = Relationships.link_entity_account(entity, account, :Wizard)
    assert %{relationship_type: _} = errors_on(changeset)
  end
end
