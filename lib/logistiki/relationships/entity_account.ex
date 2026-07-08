defmodule Logistiki.Relationships.EntityAccount do
  @moduledoc """
  A many-to-many relationship between a business entity and a virtual account,
  with effective dating and a relationship type.

  ## Fields

    * `id` — `integer()` — primary key (e.g. `1`)
    * `business_entity_id` — `integer()` — FK to `business_entities` (e.g. `1`)
    * `virtual_account_id` — `integer()` — FK to `virtual_accounts` (e.g. `10`)
    * `relationship_type` — `String.t()` — one of `relationship_types/0` (e.g. `"owner"`, `"beneficiary"`)
    * `valid_from` — `Date.t()` — when the relationship became active (e.g. `~D[2026-07-07]`)
    * `valid_to` — `Date.t() | nil` — when it ended; `nil` while still active (e.g. `nil` or `~D[2026-12-31]`)
    * `metadata` — `map()` — extensible key/value store (default `%{}`, e.g. `%{"note" => "joint account"}`)
    * `inserted_at` — `DateTime.t() | nil` — set by Ecto (e.g. `~U[2026-07-07 12:00:00Z]`)
    * `updated_at` — `DateTime.t() | nil` — set by Ecto

  ## Associations

    * `business_entity` — `belongs_to` `Logistiki.BusinessEntities.BusinessEntity`
    * `virtual_account` — `belongs_to` `Logistiki.VirtualAccounts.VirtualAccount`

  ## Unique constraint

  The pair `(business_entity_id, virtual_account_id, relationship_type)` is
  unique — but multiple relationship *types* between the same entity and
  account are allowed (e.g. `:owner` and `:beneficiary`).

  ## Example

      %Logistiki.Relationships.EntityAccount{
        id: 1,
        business_entity_id: 1,
        virtual_account_id: 10,
        relationship_type: "owner",
        valid_from: ~D[2026-07-07],
        valid_to: nil,
        metadata: %{"note" => "primary owner"}
      }
  """

  use Ecto.Schema

  import Ecto.Changeset

  @relationship_types ~w(owner beneficiary controller signatory viewer trustee related_party manager custodian)a

  schema "entity_accounts" do
    # Relationship type, one of `relationship_types/0`. Example: `\"owner\"`, `\"beneficiary\"`
    field(:relationship_type, :string)
    # Date the relationship became active (required). Example: `~D[2026-07-07]`
    field(:valid_from, :date)
    # Date the relationship ended; `nil` while active. Example: `nil` or `~D[2026-12-31]`
    field(:valid_to, :date)
    # Extensible key/value metadata. Default: `%{}`. Example: `%{\"note\" => \"joint\"}`
    field(:metadata, :map, default: %{})

    belongs_to(:business_entity, Logistiki.BusinessEntities.BusinessEntity)
    belongs_to(:virtual_account, Logistiki.VirtualAccounts.VirtualAccount)

    timestamps(type: :utc_datetime)
  end

  @typedoc """
  The `EntityAccount` struct type.

  Represents a many-to-many link between a business entity and a virtual
  account with effective dating and a relationship type.

  ## Fields

    * `id` — `integer() | nil` — primary key
    * `business_entity_id` — `integer() | nil` — FK to `business_entities`
    * `virtual_account_id` — `integer() | nil` — FK to `virtual_accounts`
    * `relationship_type` — `String.t() | nil` — e.g. `"owner"`, `"beneficiary"`
    * `valid_from` — `Date.t() | nil` — when the relationship became active
    * `valid_to` — `Date.t() | nil` — when it ended; `nil` while active
    * `metadata` — `map() | nil` — extensible metadata
    * `inserted_at` — `DateTime.t() | nil`
    * `updated_at` — `DateTime.t() | nil`

  ## Example

      %Logistiki.Relationships.EntityAccount{
        id: 1, business_entity_id: 1, virtual_account_id: 10,
        relationship_type: "owner", valid_from: ~D[2026-07-07], valid_to: nil
      }
  """
  @type t :: %__MODULE__{
          id: integer() | nil,
          business_entity_id: integer() | nil,
          virtual_account_id: integer() | nil,
          relationship_type: String.t() | nil,
          valid_from: Date.t() | nil,
          valid_to: Date.t() | nil,
          metadata: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Returns the list of allowed relationship types as atoms.

  ## Returns

    * `[atom()]` — `[:owner, :beneficiary, :controller, :signatory, :viewer,
      :trustee, :related_party, :manager, :custodian]`

  ## Examples

      iex> :owner in Logistiki.Relationships.EntityAccount.relationship_types()
      true
  """
  @doc since: "0.1.0"
  @spec relationship_types() :: [atom(), ...]
  def relationship_types, do: @relationship_types

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
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
    |> validate_required([
      :business_entity_id,
      :virtual_account_id,
      :relationship_type,
      :valid_from
    ])
    |> validate_inclusion(:relationship_type, Enum.map(@relationship_types, &Atom.to_string/1))
    |> unique_constraint(
      :relationship_type,
      name: :entity_accounts_unique_link
    )
    |> validate_date_range()
  end

  # Validates that `valid_to` is on or after `valid_from` when both are present.
  defp validate_date_range(changeset) do
    from = get_field(changeset, :valid_from)
    to = get_field(changeset, :valid_to)

    case {from, to} do
      {_, nil} ->
        changeset

      {nil, _} ->
        changeset

      {from, to} ->
        if Date.compare(to, from) == :lt do
          add_error(changeset, :valid_to, "must be on or after valid_from")
        else
          changeset
        end
    end
  end
end
