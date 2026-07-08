defmodule Logistiki.BusinessEntities do
  @moduledoc """
  The context for hierarchical business entities.

  Business entities represent legal, operational, customer, organizational, or
  ownership structures. They form a tree maintained through a closure table
  (`Logistiki.BusinessEntities.BusinessEntityClosure`).

  ## Closure table rules

    * a self-row (depth 0) is always present
    * cycles are prevented on move
    * the closure is rewritten on insert and on `move_entity/2`
    * subtree and ancestor queries are O(closure rows), not recursive CTEs
  """

  import Ecto.Query

  alias Logistiki.BusinessEntities.BusinessEntity
  alias Logistiki.BusinessEntities.BusinessEntityClosure
  alias Logistiki.Repo

  @doc """
  Creates a new business entity. When `:parent_id` is given the entity is
  linked as a child and the closure table is updated.

  ## Arguments

    * `attrs` — `map()` or `keyword()` of entity attributes:
        * `:name` — `String.t` — **required** (e.g. `"Acme Holdings"`)
        * `:entity_type` — `String.t` — **required** (e.g. `"company"`, `"trust"`)
        * `:status` — `String.t` — defaults to `"pending"`
        * `:parent_id` — `integer() | nil` — the parent entity id; `nil` for roots
        * `:legal_name` — `String.t`
        * `:jurisdiction` — `String.t` — e.g. `"US"`
        * `:external_id` — `String.t` — must be unique
        * `:metadata` — `map()`

  ## Returns

    * `{:ok, %BusinessEntity{}}` — the created entity.
    * `{:error, %Ecto.Changeset{}}` — validation failed (e.g. invalid `entity_type`).
    * `{:error, :parent_closure_missing}` — the parent has no closure rows (should not happen).

  ## Examples

      iex> {:ok, root} = Logistiki.BusinessEntities.create_entity(%{name: "Acme Holdings", entity_type: "company", status: "active"})
      iex> root.parent_id
      nil

      iex> {:ok, child} = Logistiki.BusinessEntities.create_entity(%{
      ...>   name: "Acme Trading Ltd", entity_type: "company", parent_id: root.id
      ...> })
      iex> child.parent_id
      1

      iex> {:error, changeset} = Logistiki.BusinessEntities.create_entity(%{name: "X", entity_type: "wizard"})
      iex> errors_on(changeset)[:entity_type]
      ["is invalid"]
  """
  @doc since: "0.1.0"
  @spec create_entity(map()) :: {:ok, BusinessEntity.t()} | {:error, term()}
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

  @doc """
  Updates a business entity's mutable attributes (not its parent — use
  `move_entity/2` to change the parent).

  ## Arguments

    * `entity` — `%BusinessEntity{}` — the entity to update.
    * `attrs` — `map()` or `keyword()` of attributes to change (e.g.
      `%{status: "active", legal_name: "Acme Holdings LLC"}`).

  ## Returns

    * `{:ok, %BusinessEntity{}}` — the updated entity.
    * `{:error, %Ecto.Changeset{}}` — validation failed.

  ## Examples

      iex> {:ok, updated} = Logistiki.BusinessEntities.update_entity(entity, %{status: "active"})
      iex> updated.status
      "active"
  """
  @doc since: "0.1.0"
  @spec update_entity(BusinessEntity.t(), map()) ::
          {:ok, BusinessEntity.t()} | {:error, Ecto.Changeset.t()}
  def update_entity(%BusinessEntity{} = entity, attrs) do
    entity
    |> BusinessEntity.changeset(attrs)
    |> Ecto.Changeset.change()
    |> Repo.update()
  end

  @doc """
  Fetches a single entity by id, raising if not found.

  ## Arguments

    * `id` — `integer()` — the entity primary key.

  ## Returns

    * `%BusinessEntity{}` — the entity. Raises `Ecto.NoResultsError` if not found.

  ## Examples

      iex> entity = Logistiki.BusinessEntities.get_entity!(1)
      iex> entity.name
      "Acme Holdings"
  """
  @doc since: "0.1.0"
  @spec get_entity!(integer()) :: BusinessEntity.t()
  def get_entity!(id), do: Repo.get!(BusinessEntity, id)

  @doc """
  Fetches a single entity by id.

  ## Arguments

    * `id` — `integer()` — the entity primary key.

  ## Returns

    * `{:ok, %BusinessEntity{}}` — the entity was found.
    * `{:error, :not_found}` — no entity with that id.

  ## Examples

      iex> {:ok, entity} = Logistiki.BusinessEntities.get_entity(1)
      iex> entity.name
      "Acme Holdings"

      iex> {:error, :not_found} = Logistiki.BusinessEntities.get_entity(999)
  """
  @doc since: "0.1.0"
  @spec get_entity(integer()) :: {:ok, BusinessEntity.t()} | {:error, :not_found}
  def get_entity(id) do
    case Repo.get(BusinessEntity, id) do
      nil -> {:error, :not_found}
      entity -> {:ok, entity}
    end
  end

  @doc """
  Lists entities, optionally filtered.

  ## Arguments

    * `opts` — `keyword()` of options:
        * `:status` — `String.t` — e.g. `"active"`, `"frozen"`
        * `:entity_type` — `String.t` — e.g. `"company"`, `"trust"`
        * `:parent_id` — `integer() | nil` — filter by parent; `nil` lists roots

  ## Returns

    * `[BusinessEntity.t()]` — ordered by name ascending. Empty list if none match.

  ## Examples

      iex> Logistiki.BusinessEntities.list_entities(status: "active")
      [%BusinessEntity{name: "Acme Holdings", ...}, %BusinessEntity{name: "Bluewater Trust", ...}]

      iex> Logistiki.BusinessEntities.list_entities(parent_id: nil)
      [%BusinessEntity{name: "Acme Holdings", ...}]
  """
  @doc since: "0.1.0"
  @spec list_entities(keyword()) :: [BusinessEntity.t()]
  def list_entities(opts \\ []) do
    BusinessEntity
    |> maybe_filter(:status, opts)
    |> maybe_filter(:entity_type, opts)
    |> maybe_filter(:parent_id, opts)
    |> order_by(asc: :name)
    |> Repo.all()
  end

  # Applies an optional equality filter from `opts` to `query`.
  defp maybe_filter(query, key, opts) do
    case Keyword.get(opts, key) do
      nil -> query
      value -> where(query, [e], field(e, ^key) == ^value)
    end
  end

  @doc """
  Lists direct children of `entity`.

  ## Arguments

    * `entity` — `%BusinessEntity{}` — the parent entity.

  ## Returns

    * `[BusinessEntity.t()]` — ordered by name. Empty list if no children.

  ## Examples

      iex> Logistiki.BusinessEntities.list_children(acme_holdings)
      [%BusinessEntity{name: "Acme Trading Ltd", ...}, %BusinessEntity{name: "Acme Treasury Ltd", ...}]
  """
  @doc since: "0.1.0"
  @spec list_children(BusinessEntity.t()) :: [BusinessEntity.t()]
  def list_children(%BusinessEntity{id: id}) do
    Repo.all(from(e in BusinessEntity, where: e.parent_id == ^id, order_by: [asc: e.name]))
  end

  @doc """
  Lists all descendants of `entity` (excluding the entity itself), using the
  closure table for O(rows) performance.

  ## Arguments

    * `entity` — `%BusinessEntity{}` — the root of the subtree.

  ## Returns

    * `[BusinessEntity.t()]` — ordered by name. Empty list if no descendants.

  ## Examples

      iex> Logistiki.BusinessEntities.list_descendants(acme_holdings)
      [%BusinessEntity{name: "Acme Trading Ltd", ...}, %BusinessEntity{name: "Acme Treasury Ltd", ...}]
  """
  @doc since: "0.1.0"
  @spec list_descendants(BusinessEntity.t()) :: [BusinessEntity.t()]
  def list_descendants(%BusinessEntity{id: id}) do
    descendants_query(id)
    |> order_by([e], asc: e.name)
    |> Repo.all()
  end

  @doc """
  Lists all ancestors of `entity` ordered from nearest to farthest, using the
  closure table.

  ## Arguments

    * `entity` — `%BusinessEntity{}` — the descendant entity.

  ## Returns

    * `[BusinessEntity.t()]` — ordered by `depth` ascending. Empty list if the
      entity is a root.

  ## Examples

      iex> Logistiki.BusinessEntities.list_ancestors(acme_trading)
      [%BusinessEntity{name: "Acme Holdings", ...}]
  """
  @doc since: "0.1.0"
  @spec list_ancestors(BusinessEntity.t()) :: [BusinessEntity.t()]
  def list_ancestors(%BusinessEntity{id: id}) do
    ancestors_query(id)
    |> order_by([e, c], asc: c.depth)
    |> Repo.all()
  end

  @doc """
  Moves `entity` under `new_parent` (which may be `nil` for a root), rewriting
  the closure table for the entire subtree.

  ## Arguments

    * `entity` — `%BusinessEntity{}` — the entity to move.
    * `new_parent` — one of:
        * `%BusinessEntity{}` — the new parent
        * `nil` — move to root (no parent)
        * `integer()` — the new parent's id

  ## Returns

    * `{:ok, %BusinessEntity{}}` — the moved entity with updated `parent_id`.
    * `{:error, term()}` — the move failed (rolled back).

  ## Examples

      iex> {:ok, moved} = Logistiki.BusinessEntities.move_entity(acme_trading, bluewater_trust)
      iex> moved.parent_id
      5

      iex> {:ok, root} = Logistiki.BusinessEntities.move_entity(acme_trading, nil)
      iex> root.parent_id
      nil
  """
  @doc since: "0.1.0"
  @spec move_entity(BusinessEntity.t(), BusinessEntity.t() | integer() | nil) ::
          {:ok, BusinessEntity.t()} | {:error, term()}
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

  # Resolves `new_parent` to an id: nil -> nil, struct -> id, id -> id.
  defp parent_id_from(nil), do: nil
  defp parent_id_from(%BusinessEntity{id: id}), do: id
  defp parent_id_from(id) when is_binary(id), do: id

  @doc false
  @spec insert_closure_for(BusinessEntity.t()) ::
          {:ok, :root | :child} | {:error, :parent_closure_missing}
  def insert_closure_for(%BusinessEntity{id: id, parent_id: nil}) do
    insert_self_closure(id)
    {:ok, :root}
  end

  def insert_closure_for(%BusinessEntity{id: id, parent_id: parent_id}) do
    insert_self_closure(id)
    insert_inherited_closure(id, parent_id)
    {:ok, :child}
  end

  # Inserts the self-row (depth 0) for `id`.
  defp insert_self_closure(id) do
    Repo.insert_all(
      BusinessEntityClosure,
      [%{ancestor_id: id, descendant_id: id, depth: 0, inserted_at: DateTime.utc_now(:second)}]
    )
  end

  # Inserts inherited closure rows: for every ancestor of `parent_id`, add a
  # row (ancestor, id, depth+1). Fails if the parent has no closure (should not
  # happen in normal use).
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

  # Deletes closure rows connecting this subtree to ancestors above the
  # subtree (rows whose descendant is in the subtree but ancestor is not).
  defp delete_old_closure_on_move(id) do
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

  # Rewrites the closure for a subtree moved under a new parent. For every
  # descendant d of id (including id) and every ancestor a of the new parent,
  # adds closure(a, d, depth(a, parent) + depth(id, d) + 1).
  defp link_subtree_under_new_parent(%BusinessEntity{id: _id, parent_id: nil}) do
    # When moving to root, the self-closure row already exists. The
    # delete_old_closure_on_move already removed the inherited rows.
    {:ok, :root}
  end

  defp link_subtree_under_new_parent(%BusinessEntity{id: id, parent_id: parent_id}) do
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

  # Base query for descendants (depth > 0) of `id` via the closure table.
  defp descendants_query(id) do
    from(e in BusinessEntity,
      join: c in BusinessEntityClosure,
      on: c.descendant_id == e.id,
      where: c.ancestor_id == ^id and c.depth > 0
    )
  end

  # Base query for ancestors (depth > 0) of `id` via the closure table.
  defp ancestors_query(id) do
    from(e in BusinessEntity,
      join: c in BusinessEntityClosure,
      on: c.ancestor_id == e.id,
      where: c.descendant_id == ^id and c.depth > 0
    )
  end

  @doc """
  Returns the ids of all descendants of `entity` (including itself).

  Uses the closure table directly — faster than `list_descendants/1` when only
  ids are needed (e.g. for balance aggregation queries).

  ## Arguments

    * `entity` — `%BusinessEntity{}`.

  ## Returns

    * `[integer()]` — descendant ids including `entity.id`.

  ## Examples

      iex> Logistiki.BusinessEntities.descendant_ids(acme_holdings)
      [1, 2, 3]
  """
  @doc since: "0.1.0"
  @spec descendant_ids(BusinessEntity.t()) :: [integer()]
  def descendant_ids(%BusinessEntity{id: id}) do
    Repo.all(from(c in BusinessEntityClosure, where: c.ancestor_id == ^id, select: c.descendant_id))
  end

  @doc """
  Returns the ids of all ancestors of `entity` (including itself).

  ## Arguments

    * `entity` — `%BusinessEntity{}`.

  ## Returns

    * `[integer()]` — ancestor ids including `entity.id`.

  ## Examples

      iex> Logistiki.BusinessEntities.ancestor_ids(acme_trading)
      [2, 1]
  """
  @doc since: "0.1.0"
  @spec ancestor_ids(BusinessEntity.t()) :: [integer()]
  def ancestor_ids(%BusinessEntity{id: id}) do
    Repo.all(from(c in BusinessEntityClosure, where: c.descendant_id == ^id, select: c.ancestor_id))
  end
end
