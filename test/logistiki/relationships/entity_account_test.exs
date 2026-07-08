defmodule Logistiki.Relationships.EntityAccountTest do
  use Logistiki.DataCase, async: true

  alias Logistiki.BusinessEntities
  alias Logistiki.Relationships.EntityAccount
  alias Logistiki.VirtualAccounts

  setup do
    {:ok, entity} = BusinessEntities.create_entity(%{name: "Test Entity", entity_type: "company"})

    {:ok, root} =
      VirtualAccounts.create_account(%{code: "REL_ROOT", name: "Root", account_type: "liability"})

    {:ok, account} =
      VirtualAccounts.create_account(%{
        code: "REL_ROOT:LEAF",
        name: "Leaf",
        account_type: "client",
        currency: "USD",
        posting_allowed: true,
        parent_id: root.id
      })

    %{entity: entity, account: account}
  end

  describe "relationship_types/0" do
    test "returns all relationship types" do
      types = EntityAccount.relationship_types()

      for t <- [
            :owner,
            :beneficiary,
            :controller,
            :signatory,
            :viewer,
            :trustee,
            :related_party,
            :manager,
            :custodian
          ] do
        assert t in types
      end
    end
  end

  describe "changeset/2" do
    test "validates required fields" do
      changeset = EntityAccount.changeset(%EntityAccount{}, %{})
      refute changeset.valid?
      assert changeset.errors[:business_entity_id]
      assert changeset.errors[:virtual_account_id]
      assert changeset.errors[:relationship_type]
      assert changeset.errors[:valid_from]
    end

    test "validates relationship_type inclusion" do
      changeset =
        EntityAccount.changeset(%EntityAccount{}, %{
          business_entity_id: 1,
          virtual_account_id: 1,
          relationship_type: "wizard",
          valid_from: ~D[2026-07-07]
        })

      refute changeset.valid?
      assert changeset.errors[:relationship_type]
    end

    test "validates date range" do
      changeset =
        EntityAccount.changeset(%EntityAccount{}, %{
          business_entity_id: 1,
          virtual_account_id: 1,
          relationship_type: "owner",
          valid_from: ~D[2026-07-10],
          valid_to: ~D[2026-07-01]
        })

      refute changeset.valid?
      assert changeset.errors[:valid_to]
    end

    test "accepts valid attrs" do
      changeset =
        EntityAccount.changeset(%EntityAccount{}, %{
          business_entity_id: 1,
          virtual_account_id: 1,
          relationship_type: "owner",
          valid_from: ~D[2026-07-07]
        })

      assert changeset.valid?
    end
  end
end
