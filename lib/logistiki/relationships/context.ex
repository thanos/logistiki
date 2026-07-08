defmodule Logistiki.Relationships do
  @moduledoc """
  The context for entity-to-account relationships.

  Business entities and virtual accounts are separate hierarchies. They connect
  through relationships that support many-to-many links, multiple relationship
  types between the same pair, and effective dating.
  """

  import Ecto.Query

  alias Logistiki.BusinessEntities.BusinessEntity
  alias Logistiki.Relationships.EntityAccount
  alias Logistiki.Repo
  alias Logistiki.VirtualAccounts.VirtualAccount

  @doc "Links `entity` to `account` with `relationship_type` and optional attrs (`:valid_from`, `:valid_to`, `:metadata`)."
  def link_entity_account(entity, account, relationship_type, attrs \\ %{})

  def link_entity_account(%BusinessEntity{id: entity_id}, %VirtualAccount{id: account_id}, type, attrs) do
    link_entity_account(entity_id, account_id, type, attrs)
  end

  def link_entity_account(entity_id, account_id, relationship_type, attrs)
      when (is_integer(entity_id) or is_binary(entity_id)) and
             (is_integer(account_id) or is_binary(account_id)) do
    attrs =
      Map.merge(
        %{
          business_entity_id: entity_id,
          virtual_account_id: account_id,
          relationship_type: Atom.to_string(relationship_type),
          valid_from: Date.utc_today()
        },
        Map.new(attrs)
      )

    %EntityAccount{}
    |> EntityAccount.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Unlinks `entity` and `account` for `relationship_type` by setting `valid_to` to today."
  def unlink_entity_account(%BusinessEntity{id: entity_id}, %VirtualAccount{id: account_id}, relationship_type) do
    unlink_entity_account(entity_id, account_id, relationship_type)
  end

  def unlink_entity_account(entity_id, account_id, relationship_type) do
    type = Atom.to_string(relationship_type)

    from(r in EntityAccount,
      where:
        r.business_entity_id == ^entity_id and
          r.virtual_account_id == ^account_id and
          r.relationship_type == ^type and
          is_nil(r.valid_to)
    )
    |> Repo.update_all(set: [valid_to: Date.utc_today()])
  end

  @doc "Lists accounts linked to `entity`, optionally filtered by `:relationship_type` or `:at` (effective date)."
  def list_accounts_for_entity(entity_or_id, opts \\ [])

  def list_accounts_for_entity(%BusinessEntity{id: id}, opts), do: list_accounts_for_entity(id, opts)

  def list_accounts_for_entity(entity_id, opts) when is_integer(entity_id) or is_binary(entity_id) do
    direct_accounts_query(entity_id, opts)
    |> order_by([a], asc: a.code)
    |> Repo.all()
  end

  @doc "Lists accounts linked to `entity` or any of its descendants."
  def list_accounts_for_entity_tree(%BusinessEntity{} = entity, opts \\ []) do
    entity_ids = Logistiki.BusinessEntities.descendant_ids(entity)

    tree_accounts_query(entity_ids, opts)
    |> order_by([a], asc: a.code)
    |> Repo.all()
  end

  @doc "Lists entities linked to `account`, optionally filtered by `:relationship_type` or `:at`."
  def list_entities_for_account(account_or_id, opts \\ [])

  def list_entities_for_account(%VirtualAccount{id: id}, opts), do: list_entities_for_account(id, opts)

  def list_entities_for_account(account_id, opts) when is_integer(account_id) or is_binary(account_id) do
    direct_entities_query(account_id, opts)
    |> order_by([e], asc: e.name)
    |> Repo.all()
  end

  defp direct_accounts_query(entity_id, opts) do
    from a in VirtualAccount,
      join: r in EntityAccount, on: r.virtual_account_id == a.id,
      where: r.business_entity_id == ^entity_id,
      where: ^effective_filter(opts),
      where: ^type_filter(opts)
  end

  defp tree_accounts_query(entity_ids, opts) do
    from a in VirtualAccount,
      join: r in EntityAccount, on: r.virtual_account_id == a.id,
      where: r.business_entity_id in ^entity_ids,
      where: ^effective_filter(opts),
      where: ^type_filter(opts)
  end

  defp direct_entities_query(account_id, opts) do
    from e in BusinessEntity,
      join: r in EntityAccount, on: r.business_entity_id == e.id,
      where: r.virtual_account_id == ^account_id,
      where: ^effective_filter(opts),
      where: ^type_filter(opts)
  end

  defp effective_filter(opts) do
    case Keyword.get(opts, :at) do
      nil -> dynamic([_, r], is_nil(r.valid_to))
      date -> dynamic([_, r], r.valid_from <= ^date and (is_nil(r.valid_to) or r.valid_to >= ^date))
    end
  end

  defp type_filter(opts) do
    case Keyword.get(opts, :relationship_type) do
      nil -> dynamic(true)
      type -> dynamic([_, r], r.relationship_type == ^Atom.to_string(type))
    end
  end
end
