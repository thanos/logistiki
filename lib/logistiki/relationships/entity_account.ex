defmodule Logistiki.Relationships.EntityAccount do
  @moduledoc """
  A many-to-many relationship between a business entity and a virtual account,
  with effective dating and a relationship type.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @relationship_types ~w(owner beneficiary controller signatory viewer trustee related_party manager custodian)a

  schema "entity_accounts" do
    field :relationship_type, :string
    field :valid_from, :date
    field :valid_to, :date
    field :metadata, :map, default: %{}

    belongs_to :business_entity, Logistiki.BusinessEntities.BusinessEntity
    belongs_to :virtual_account, Logistiki.VirtualAccounts.VirtualAccount

    timestamps(type: :utc_datetime)
  end

  def relationship_types, do: @relationship_types

  @doc false
  def changeset(link, attrs) do
    link
    |> cast(attrs, [
      :business_entity_id,
      :virtual_account_id,
      :relationship_type,
      :valid_from,
      :valid_to,
      :metadata
    ])
    |> validate_required([:business_entity_id, :virtual_account_id, :relationship_type, :valid_from])
    |> validate_inclusion(:relationship_type, Enum.map(@relationship_types, &Atom.to_string/1))
    |> unique_constraint(
      :relationship_type,
      name: :entity_accounts_unique_link
    )
    |> validate_date_range()
  end

  defp validate_date_range(changeset) do
    from = get_field(changeset, :valid_from)
    to = get_field(changeset, :valid_to)

    case {from, to} do
      {_, nil} -> changeset
      {nil, _} -> changeset
      {from, to} ->
        if Date.compare(to, from) == :lt do
          add_error(changeset, :valid_to, "must be on or after valid_from")
        else
          changeset
        end
    end
  end
end
