defmodule Logistiki.BusinessEntities do
  @moduledoc """
  The context for hierarchical business entities.

  Business entities represent legal, operational, customer, organizational, or
  ownership structures. They form a tree maintained through a closure table
  (`Logistiki.BusinessEntities.BusinessEntityClosure`).
  """

  import Ecto.Query

  alias Logistiki.BusinessEntities.BusinessEntity
  alias Logistiki.BusinessEntities.BusinessEntityClosure
  alias Logistiki.Repo

  @doc "Creates a new business entity. When `:parent_id` is given the entity is linked as a child."
  def create_entity(attrs \\ %{}) do
    attrs = Map.new(attrs)

    Repo.transaction(fn ->
      with {:ok, entity} <-
             %BusinessEntity{}
             |> BusinessEntity.changeset(attrs)
             |> Repo.insert(),
           {:ok, _} <- insert_closure_for(entity) do
        entity
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Updates a business entity's mutable attributes (not its parent)."
  def update_entity(%BusinessEntity{} = entity, attrs) do
    entity
    |> BusinessEntity.changeset(attrs)
    |> Ecto.Changeset.change()
    |> Repo.update()
  end

  @doc "Fetches a single entity, raising if not found."
  def get_entity!(id), do: Repo.get!(BusinessEntity, id)

  @doc "Fetches a single entity, returning `{:ok, entity}` or `{:error, :not_found}`."
  def get_entity(id) do
    case Repo.get(BusinessEntity, id) do
      nil -> {:error, :not_found}
      entity -> {:ok, entity}
    end
  end

  @doc "Lists entities, optionally filtered by `:status`, `:entity_type`, or `:parent_id`."
  def list_entities(opts \\ []) do
    BusinessEntity
    |> maybe_filter(:status, opts)
    |> maybe_filter(:entity_type, opts)
    |> maybe_filter(:parent_id, opts)
    |> order_by(asc: :name)
    |> Repo.all()
  end

  defp maybe_filter(query, key, opts) do
    case Keyword.get(opts, key) do
      nil -> query
      value -> where(query, [e], field(e, ^key) == ^value)
    end
  end

  @doc "Lists direct children of `entity`."
  def list_children(%BusinessEntity{id: id}) do
    Repo.all(from e in BusinessEntity, where: e.parent_id == ^id, order_by: [asc: e.name])
  end

  @doc "Lists all descendants of `entity` (excluding the entity itself)."
  def list_descendants(%BusinessEntity{id: id}) do
    descendants_query(id)
    |> order_by([e], asc: e.name)
    |> Repo.all()
  end

  @doc "Lists all ancestors of `entity` ordered from nearest to farthest."
  def list_ancestors(%BusinessEntity{id: id}) do
    ancestors_query(id)
    |> order_by([e, c], asc: c.depth)
    |> Repo.all()
  end

  @doc "Moves `entity` under `new_parent` (which may be `nil` for a root), rewriting the closure."
  def move_entity(%BusinessEntity{} = entity, new_parent) do
    new_parent_id = parent_id_from(new_parent)

    Repo.transaction(fn ->
      # Remove old closure rows that link this subtree to its old ancestors.
      delete_old_closure_on_move(entity.id)

      with {:ok, updated} <-
             entity
             |> BusinessEntity.changeset(%{parent_id: new_parent_id})
             |> Ecto.Changeset.change()
             |> Repo.update(),
           {:ok, _} <- link_subtree_under_new_parent(updated) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp parent_id_from(nil), do: nil
  defp parent_id_from(%BusinessEntity{id: id}), do: id
  defp parent_id_from(id) when is_binary(id), do: id

  @doc false
  def insert_closure_for(%BusinessEntity{id: id, parent_id: nil}) do
    insert_self_closure(id)
    {:ok, :root}
  end

  def insert_closure_for(%BusinessEntity{id: id, parent_id: parent_id}) do
    insert_self_closure(id)
    insert_inherited_closure(id, parent_id)
    {:ok, :child}
  end

  defp insert_self_closure(id) do
    Repo.insert_all(
      BusinessEntityClosure,
      [%{ancestor_id: id, descendant_id: id, depth: 0, inserted_at: DateTime.utc_now(:second)}]
    )
  end

  defp insert_inherited_closure(id, parent_id) do
    rows =
      from(c in BusinessEntityClosure,
        where: c.descendant_id == ^parent_id,
        select: {c.ancestor_id, c.depth}
      )
      |> Repo.all()
      |> Enum.map(fn {ancestor_id, depth} ->
        %{
          ancestor_id: ancestor_id,
          descendant_id: id,
          depth: depth + 1,
          inserted_at: DateTime.utc_now(:second)
        }
      end)

    if rows == [] do
      # Parent not yet in closure: fail loudly so callers notice the inconsistency.
      {:error, :parent_closure_missing}
    else
      Repo.insert_all(BusinessEntityClosure, rows)
    end
  end

  defp delete_old_closure_on_move(id) do
    # Delete closure rows connecting this subtree to ancestors above the subtree.
    from(c in BusinessEntityClosure,
      where:
        c.descendant_id in subquery(
          from(sc in BusinessEntityClosure, where: sc.ancestor_id == ^id, select: sc.descendant_id)
        ) and
          c.ancestor_id not in subquery(
            from(sc in BusinessEntityClosure, where: sc.ancestor_id == ^id, select: sc.ancestor_id)
          )
    )
    |> Repo.delete_all()

    :ok
  end

  defp link_subtree_under_new_parent(%BusinessEntity{id: id, parent_id: nil}) do
    insert_self_closure(id)
    {:ok, :root}
  end

  defp link_subtree_under_new_parent(%BusinessEntity{id: id, parent_id: parent_id}) do
    # For every descendant d of id (including id) and every ancestor a of new parent,
    # add closure(a, d, depth(a, parent) + depth(id, d) + 1).
    descendant_rows =
      from(d in BusinessEntityClosure,
        where: d.ancestor_id == ^id,
        select: {d.descendant_id, d.depth}
      )
      |> Repo.all()

    ancestor_rows =
      from(a in BusinessEntityClosure,
        where: a.descendant_id == ^parent_id,
        select: {a.ancestor_id, a.depth}
      )
      |> Repo.all()

    new_rows =
      for {d_id, d_depth} <- descendant_rows,
          {a_id, a_depth} <- ancestor_rows do
        %{
          ancestor_id: a_id,
          descendant_id: d_id,
          depth: a_depth + d_depth + 1,
          inserted_at: DateTime.utc_now(:second)
        }
      end

    Repo.insert_all(BusinessEntityClosure, new_rows)
    {:ok, :linked}
  end

  defp descendants_query(id) do
    from e in BusinessEntity,
      join: c in BusinessEntityClosure, on: c.descendant_id == e.id,
      where: c.ancestor_id == ^id and c.depth > 0
  end

  defp ancestors_query(id) do
    from e in BusinessEntity,
      join: c in BusinessEntityClosure, on: c.ancestor_id == e.id,
      where: c.descendant_id == ^id and c.depth > 0
  end

  @doc "Returns the ids of all descendants of `entity` (including itself)."
  def descendant_ids(%BusinessEntity{id: id}) do
    Repo.all(from c in BusinessEntityClosure, where: c.ancestor_id == ^id, select: c.descendant_id)
  end

  @doc "Returns the ids of all ancestors of `entity` (including itself)."
  def ancestor_ids(%BusinessEntity{id: id}) do
    Repo.all(from c in BusinessEntityClosure, where: c.descendant_id == ^id, select: c.ancestor_id)
  end
end
