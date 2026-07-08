defmodule Logistiki.VirtualAccounts.VirtualAccountClosure do
  @moduledoc """
  Closure table for the virtual account hierarchy.

  Each row records that `ancestor` is an ancestor of `descendant` at `depth`.
  A self-row has depth 0.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "virtual_account_closure" do
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
