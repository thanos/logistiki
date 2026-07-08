defmodule Logistiki.BusinessEntities.BusinessEntity do
  @moduledoc """
  A hierarchical business entity: legal, operational, customer, organizational,
  or ownership structure.

  Entities form a tree maintained through a closure table
  (`Logistiki.BusinessEntities.BusinessEntityClosure`). Each entity may have a
  `parent_id` pointing to its parent; roots have `parent_id: nil`.

  ## Fields

    * `id` — `integer()` — primary key (e.g. `1`)
    * `parent_id` — `integer() | nil` — self-reference; `nil` for roots (e.g. `nil` or `1`)
    * `name` — `String.t()` — display name (required) (e.g. `"Acme Holdings"`)
    * `legal_name` — `String.t() | nil` — legal name (e.g. `"Acme Holdings LLC"`)
    * `entity_type` — `String.t()` — one of `types/0` (default `"company"`, e.g. `"trust"`, `"individual"`)
    * `status` — `String.t()` — one of `statuses/0` (default `"pending"`, e.g. `"active"`, `"frozen"`)
    * `jurisdiction` — `String.t() | nil` — e.g. `"US"`, `"EU"`, `"GB"`
    * `external_id` — `String.t() | nil` — unique external reference (e.g. `"crm_12345"`)
    * `metadata` — `map()` — extensible key/value store (default `%{}`, e.g. `%{"risk_score" => "low"}`)
    * `inserted_at` — `DateTime.t() | nil` — set by Ecto timestamps (e.g. `~U[2026-07-07 12:00:00Z]`)
    * `updated_at` — `DateTime.t() | nil` — set by Ecto timestamps

  ## Associations

    * `parent` — `belongs_to` `__MODULE__` — the parent entity (via `parent_id`)
    * `children` — `has_many` `__MODULE__` — direct child entities

  ## Example

      %Logistiki.BusinessEntities.BusinessEntity{
        id: 1,
        parent_id: nil,
        name: "Acme Holdings",
        legal_name: "Acme Holdings LLC",
        entity_type: "company",
        status: "active",
        jurisdiction: "US",
        external_id: "crm_12345",
        metadata: %{"risk_score" => "low"},
        inserted_at: ~U[2026-07-07 12:00:00Z],
        updated_at: ~U[2026-07-07 12:00:00Z]
      }
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending active inactive frozen closed)a
  @types ~w(individual company trust partnership fund bank branch department counterparty internal)a

  schema "business_entities" do
    # Display name of the entity (required). Example: `\"Acme Holdings\"`
    field :name, :string
    # Legal name of the entity. Example: `\"Acme Holdings LLC\"`
    field :legal_name, :string
    # Entity type, one of `types/0`. Default: `\"company\"`. Example: `\"trust\"`
    field :entity_type, :string, default: "company"
    # Entity status, one of `statuses/0`. Default: `\"pending\"`. Example: `\"active\"`
    field :status, :string, default: "pending"
    # Jurisdiction code. Example: `\"US\"`, `\"EU\"`, `\"GB\"`
    field :jurisdiction, :string
    # Unique external reference. Example: `\"crm_12345\"`
    field :external_id, :string
    # Extensible key/value metadata. Default: `%{}`. Example: `%{\"risk_score\" => \"low\"}`
    field :metadata, :map, default: %{}

    belongs_to :parent, __MODULE__, foreign_key: :parent_id
    has_many :children, __MODULE__, foreign_key: :parent_id

    timestamps(type: :utc_datetime)
  end

  @typedoc """
  The `BusinessEntity` struct type.

  Represents a hierarchical business entity with provenance, status, and
  extensible metadata.

  ## Fields

    * `id` — `integer() | nil` — primary key (e.g. `1`)
    * `parent_id` — `integer() | nil` — parent entity id; `nil` for roots
    * `name` — `String.t() | nil` — display name (e.g. `"Acme Holdings"`)
    * `legal_name` — `String.t() | nil` — legal name
    * `entity_type` — `String.t() | nil` — e.g. `"company"`, `"trust"`
    * `status` — `String.t() | nil` — e.g. `"active"`, `"frozen"`
    * `jurisdiction` — `String.t() | nil` — e.g. `"US"`
    * `external_id` — `String.t() | nil` — unique external reference
    * `metadata` — `map() | nil` — extensible metadata
    * `inserted_at` — `DateTime.t() | nil`
    * `updated_at` — `DateTime.t() | nil`

  ## Example

      %Logistiki.BusinessEntities.BusinessEntity{
        id: 1, parent_id: nil, name: "Acme Holdings",
        entity_type: "company", status: "active"
      }
  """
  @type t :: %__MODULE__{
          id: integer() | nil,
          parent_id: integer() | nil,
          name: String.t() | nil,
          legal_name: String.t() | nil,
          entity_type: String.t() | nil,
          status: String.t() | nil,
          jurisdiction: String.t() | nil,
          external_id: String.t() | nil,
          metadata: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Returns the list of allowed entity statuses as atoms.

  ## Returns

    * `[atom()]` — `[:pending, :active, :inactive, :frozen, :closed]`

  ## Examples

      iex> Logistiki.BusinessEntities.BusinessEntity.statuses()
      [:pending, :active, :inactive, :frozen, :closed]
  """
  @doc since: "0.1.0"
  @spec statuses() :: [atom(), ...]
  def statuses, do: @statuses

  @doc """
  Returns the list of allowed entity types as atoms.

  ## Returns

    * `[atom()]` — `[:individual, :company, :trust, :partnership, :fund,
      :bank, :branch, :department, :counterparty, :internal]`

  ## Examples

      iex> :company in Logistiki.BusinessEntities.BusinessEntity.types()
      true
  """
  @doc since: "0.1.0"
  @spec types() :: [atom(), ...]
  def types, do: @types

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(entity, attrs) do
    entity
    |> cast(attrs, [:name, :legal_name, :entity_type, :status, :jurisdiction, :external_id, :parent_id, :metadata])
    |> validate_required([:name, :entity_type, :status])
    |> validate_inclusion(:status, Enum.map(@statuses, &Atom.to_string/1))
    |> validate_inclusion(:entity_type, Enum.map(@types, &Atom.to_string/1))
    |> unique_constraint(:external_id)
  end
end
