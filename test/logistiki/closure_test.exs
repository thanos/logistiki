defmodule Logistiki.ClosureTest do
  use Logistiki.DataCase, async: true

  alias Logistiki.BusinessEntities.BusinessEntityClosure
  alias Logistiki.VirtualAccounts.VirtualAccountClosure

  describe "BusinessEntityClosure.changeset/2" do
    test "casts ancestor_id, descendant_id, depth" do
      cs =
        BusinessEntityClosure.changeset(%BusinessEntityClosure{}, %{
          ancestor_id: 1,
          descendant_id: 2,
          depth: 1
        })

      assert cs.valid?
    end
  end

  describe "VirtualAccountClosure.changeset/2" do
    test "casts ancestor_id, descendant_id, depth" do
      cs =
        VirtualAccountClosure.changeset(%VirtualAccountClosure{}, %{
          ancestor_id: 1,
          descendant_id: 2,
          depth: 1
        })

      assert cs.valid?
    end
  end
end
