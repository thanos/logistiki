defmodule Logistiki.BusinessEntities.MiscTest do
  use Logistiki.DataCase, async: true

  alias Logistiki.BusinessEntities
  alias Logistiki.BusinessEntities.BusinessEntity

  describe "BusinessEntity enum functions" do
    test "statuses/0 returns all statuses" do
      statuses = BusinessEntity.statuses()

      for s <- [:pending, :active, :inactive, :frozen, :closed] do
        assert s in statuses
      end
    end

    test "types/0 returns all types" do
      types = BusinessEntity.types()

      for t <- [
            :individual,
            :company,
            :trust,
            :partnership,
            :fund,
            :bank,
            :branch,
            :department,
            :counterparty,
            :internal
          ] do
        assert t in types
      end
    end
  end

  describe "get_entity/1" do
    test "returns {:ok, entity} when found" do
      {:ok, entity} = BusinessEntities.create_entity(%{name: "Get Test", entity_type: "company"})
      assert {:ok, ^entity} = BusinessEntities.get_entity(entity.id)
    end

    test "returns {:error, :not_found} when not found" do
      assert {:error, :not_found} = BusinessEntities.get_entity(999_999)
    end
  end

  describe "update_entity/2" do
    test "updates entity attributes" do
      {:ok, entity} = BusinessEntities.create_entity(%{name: "Update Test", entity_type: "company"})

      {:ok, updated} =
        BusinessEntities.update_entity(entity, %{status: "active", legal_name: "Update Test LLC"})

      assert updated.status == "active"
      assert updated.legal_name == "Update Test LLC"
    end
  end

  describe "list_entities/1" do
    test "lists entities filtered by status" do
      BusinessEntities.create_entity(%{
        name: "List Active",
        entity_type: "company",
        status: "active"
      })

      BusinessEntities.create_entity(%{
        name: "List Pending",
        entity_type: "company",
        status: "pending"
      })

      active = BusinessEntities.list_entities(status: "active")
      assert Enum.all?(active, &(&1.status == "active"))
    end

    test "lists entities filtered by entity_type" do
      BusinessEntities.create_entity(%{name: "List Trust", entity_type: "trust"})
      trusts = BusinessEntities.list_entities(entity_type: "trust")
      assert Enum.all?(trusts, &(&1.entity_type == "trust"))
    end
  end

  describe "ancestor_ids/1" do
    test "returns ancestor ids including self" do
      {:ok, parent} = BusinessEntities.create_entity(%{name: "Anc Parent", entity_type: "company"})

      {:ok, child} =
        BusinessEntities.create_entity(%{
          name: "Anc Child",
          entity_type: "company",
          parent_id: parent.id
        })

      ancestors = BusinessEntities.ancestor_ids(child) |> Enum.sort()
      assert ancestors == Enum.sort([child.id, parent.id])
    end
  end
end
