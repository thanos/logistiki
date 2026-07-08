defmodule Logistiki.VirtualAccounts.VirtualAccountClosure do
  @moduledoc """
  Closure table for the virtual account hierarchy.

  Each row records that `ancestor` is an ancestor of `descendant` at `depth`.
  A self-row has depth 0. The closure table is maintained by
  `Logistiki.VirtualAccounts` on insert and move.

  ## Fields

    * `id` — `integer()` — primary key (e.g. `1`)
    * `ancestor_id` — `integer()` — the ancestor account id (e.g. `1` for `ASSETS`)
    * `descendant_id` — `integer()` — the descendant account id (e.g. `4` for `ASSETS:CASH:USD:NOSTRO`)
    * `depth` — `integer()` — 0 for self, 1 for direct child, 2 for grandchild (e.g. `3`)
    * `inserted_at` — `DateTime.t() | nil` — set on insert (no `updated_at`; e.g. `~U[2026-07-07 12:00:00Z]`)

  ## Example

      %Logistiki.VirtualAccounts.VirtualAccountClosure{
        id: 1,
        ancestor_id: 1,    # ASSETS
        descendant_id: 4,  # ASSETS:CASH:USD:NOSTRO
        depth: 3,
        inserted_at: ~U[2026-07-07 12:00:00Z]
      }
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "virtual_account_closure" do
    # Ancestor account id. Example: `1` (ASSETS)
    field :ancestor_id, :integer
    # Descendant account id. Example: `4` (ASSETS:CASH:USD:NOSTRO)
    field :descendant_id, :integer
    # Depth in the hierarchy: 0 for self, 1 for direct child, 2 for grandchild. Example: `3`
    field :depth, :integer

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @typedoc """
  The `VirtualAccountClosure` struct type.

  A row in the closure table recording that `ancestor_id` is an ancestor of
  `descendant_id` at the given `depth`.

  ## Fields

    * `id` — `integer() | nil` — primary key
    * `ancestor_id` — `integer() | nil` — ancestor account id (e.g. `1`)
    * `descendant_id` — `integer() | nil` — descendant account id (e.g. `4`)
    * `depth` — `integer() | nil` — 0 for self, 1 for child, 2 for grandchild
    * `inserted_at` — `DateTime.t() | nil` — set on insert (no `updated_at`)

  ## Example

      %Logistiki.VirtualAccounts.VirtualAccountClosure{
        ancestor_id: 1, descendant_id: 4, depth: 3
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
