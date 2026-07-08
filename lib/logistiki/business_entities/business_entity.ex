defmodule Logistiki.BusinessEntities.BusinessEntity do
  @moduledoc """
  A hierarchical business entity: legal, operational, customer, organizational,
  or ownership structure.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending active inactive frozen closed)a
  @types ~w(individual company trust partnership fund bank branch department counterparty internal)a

  schema "business_entities" do
    field :name, :string
    field :legal_name, :string
    field :entity_type, :string, default: "company"
    field :status, :string, default: "pending"
    field :jurisdiction, :string
    field :external_id, :string
    field :metadata, :map, default: %{}

    belongs_to :parent, __MODULE__, foreign_key: :parent_id

    has_many :children, __MODULE__, foreign_key: :parent_id

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses
  def types, do: @types

  @doc false
  def changeset(entity, attrs) do
    entity
    |> cast(attrs, [:name, :legal_name, :entity_type, :status, :jurisdiction, :external_id, :parent_id, :metadata])
    |> validate_required([:name, :entity_type, :status])
    |> validate_inclusion(:status, Enum.map(@statuses, &Atom.to_string/1))
    |> validate_inclusion(:entity_type, Enum.map(@types, &Atom.to_string/1))
    |> unique_constraint(:external_id)
  end
end
