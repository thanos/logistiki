defmodule Logistiki.BusinessEntities.BusinessEntityClosure do
  @moduledoc """
  Closure table for the business entity hierarchy.

  Each row records that `ancestor` is an ancestor of `descendant` at `depth`.
  A self-row has depth 0.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "business_entity_closure" do
    field :ancestor_id, :integer
    field :descendant_id, :integer
    field :depth, :integer

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(closure, attrs) do
    cast(closure, attrs, [:ancestor_id, :descendant_id, :depth])
  end
end
