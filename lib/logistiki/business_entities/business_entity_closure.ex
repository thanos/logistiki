defmodule Logistiki.BusinessEntities.BusinessEntityClosure do
  @moduledoc """
  Closure table for the business entity hierarchy.

  Each row records that `ancestor` is an ancestor of `descendant` at `depth`.
  A self-row has depth 0. The closure table is maintained by
  `Logistiki.BusinessEntities` on insert and move.

  ## Fields

    * `id` — `integer()` — primary key (e.g. `1`)
    * `ancestor_id` — `integer()` — the ancestor entity id (e.g. `1` for Acme Holdings)
    * `descendant_id` — `integer()` — the descendant entity id (e.g. `2` for Acme Trading Ltd)
    * `depth` — `integer()` — 0 for self, 1 for direct child, 2 for grandchild (e.g. `1`)
    * `inserted_at` — `DateTime.t() | nil` — set on insert (no `updated_at`; e.g. `~U[2026-07-07 12:00:00Z]`)

  ## Example

      %Logistiki.BusinessEntities.BusinessEntityClosure{
        id: 1,
        ancestor_id: 1,    # Acme Holdings
        descendant_id: 2,  # Acme Trading Ltd
        depth: 1,
        inserted_at: ~U[2026-07-07 12:00:00Z]
      }
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "business_entity_closure" do
    # Ancestor entity id. Example: `1` (Acme Holdings)
    field(:ancestor_id, :integer)
    # Descendant entity id. Example: `2` (Acme Trading Ltd)
    field(:descendant_id, :integer)
    # Depth in the hierarchy: 0 for self, 1 for direct child, 2 for grandchild. Example: `1`
    field(:depth, :integer)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @typedoc """
  The `BusinessEntityClosure` struct type.

  A row in the closure table recording that `ancestor_id` is an ancestor of
  `descendant_id` at the given `depth`.

  ## Fields

    * `id` — `integer() | nil` — primary key
    * `ancestor_id` — `integer() | nil` — ancestor entity id (e.g. `1`)
    * `descendant_id` — `integer() | nil` — descendant entity id (e.g. `2`)
    * `depth` — `integer() | nil` — 0 for self, 1 for child, 2 for grandchild
    * `inserted_at` — `DateTime.t() | nil` — set on insert

  ## Example

      %Logistiki.BusinessEntities.BusinessEntityClosure{
        ancestor_id: 1, descendant_id: 2, depth: 1
      }
  """
  @type t :: %__MODULE__{
          id: integer() | nil,
          ancestor_id: integer() | nil,
          descendant_id: integer() | nil,
          depth: integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(closure, attrs) do
    cast(closure, attrs, [:ancestor_id, :descendant_id, :depth])
  end
end
