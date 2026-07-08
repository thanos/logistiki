defmodule Logistiki.BusinessEntitiesTest do
  use Logistiki.DataCase, async: true

  alias Logistiki.BusinessEntities

  describe "create_entity/1" do
    test "creates a root entity" do
      assert {:ok, entity} = BusinessEntities.create_entity(%{name: "Acme Holdings", entity_type: "company"})
      assert entity.parent_id == nil
      assert entity.status == "pending"

      assert BusinessEntities.ancestor_ids(entity) == [entity.id]
      assert BusinessEntities.descendant_ids(entity) == [entity.id]
    end

    test "creates a child entity and links the closure" do
      assert {:ok, parent} = BusinessEntities.create_entity(%{name: "Acme Holdings", entity_type: "company"})

      assert {:ok, child} =
               BusinessEntities.create_entity(%{
                 name: "Acme Trading Ltd",
                 entity_type: "company",
                 parent_id: parent.id
               })

      ancestors = BusinessEntities.ancestor_ids(child) |> Enum.sort()
      descendants = BusinessEntities.descendant_ids(parent) |> Enum.sort()

      assert ancestors == Enum.sort([child.id, parent.id])
      assert descendants == Enum.sort([child.id, parent.id])

      [listed] = BusinessEntities.list_children(parent)
      assert listed.id == child.id

      [listed_desc] = BusinessEntities.list_descendants(parent)
      assert listed_desc.id == child.id

      [listed_anc] = BusinessEntities.list_ancestors(child)
      assert listed_anc.id == parent.id
    end

    test "rejects invalid status and entity_type" do
      assert {:error, changeset} =
               BusinessEntities.create_entity(%{name: "X", entity_type: "wizard", status: "ghost"})

      assert %{:entity_type => _, :status => _} = errors_on(changeset)
    end
  end

  describe "move_entity/2" do
    test "moves a subtree under a new parent" do
      {:ok, a} = BusinessEntities.create_entity(%{name: "A", entity_type: "company"})
      {:ok, b} = BusinessEntities.create_entity(%{name: "B", entity_type: "company", parent_id: a.id})
      {:ok, c} = BusinessEntities.create_entity(%{name: "C", entity_type: "company", parent_id: b.id})
      {:ok, d} = BusinessEntities.create_entity(%{name: "D", entity_type: "company"})

      assert {:ok, moved} = BusinessEntities.move_entity(c, d)

      assert moved.parent_id == d.id
      ancestors = BusinessEntities.ancestor_ids(c) |> Enum.sort()
      assert ancestors == Enum.sort([c.id, d.id])
      refute a.id in BusinessEntities.descendant_ids(d)
      assert c.id in BusinessEntities.descendant_ids(d)
    end
  end
end
