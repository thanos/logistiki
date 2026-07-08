defmodule Logistiki.Relationships do
  @moduledoc """
  The context for entity-to-account relationships.

  Business entities and virtual accounts are separate hierarchies. They connect
  through relationships that support many-to-many links, multiple relationship
  types between the same pair, and effective dating.

  ## Effective dating

  Each relationship has `valid_from` and `valid_to` (`nil` while active). List
  functions accept an `:at` option (a `Date`) to filter relationships active at
  a point in time.
  """

  import Ecto.Query

  alias Logistiki.BusinessEntities.BusinessEntity
  alias Logistiki.Relationships.EntityAccount
  alias Logistiki.Repo
  alias Logistiki.VirtualAccounts.VirtualAccount

  @doc """
  Links `entity` to `account` with `relationship_type` and optional attributes.

  ## Arguments

    * `entity` — `%BusinessEntity{}` or `integer()` entity id.
    * `account` — `%VirtualAccount{}` or `integer()` account id.
    * `relationship_type` — `atom()` — one of `EntityAccount.relationship_types/0`
      (e.g. `:owner`, `:beneficiary`).
    * `attrs` — `map()` of optional attributes:
        * `:valid_from` — `Date.t` — defaults to `Date.utc_today/0`
        * `:valid_to` — `Date.t` — defaults to `nil` (active)
        * `:metadata` — `map()`

  ## Returns

    * `{:ok, %EntityAccount{}}` — the link was created.
    * `{:error, %Ecto.Changeset{}}` — validation failed (e.g. unknown
      `relationship_type`, duplicate `(entity, account, type)` triple).

  ## Examples

      iex> {:ok, link} = Logistiki.Relationships.link_entity_account(acme_entity, nostro_account, :owner)
      iex> link.relationship_type
      "owner"

      iex> {:ok, link} = Logistiki.Relationships.link_entity_account(acme_entity, nostro_account, :beneficiary,
      ...>   valid_from: ~D[2026-01-01], metadata: %{note: "joint"}
      ...> )
      iex> link.metadata
      %{"note" => "joint"}

      iex> {:error, changeset} = Logistiki.Relationships.link_entity_account(entity, account, :wizard)
      iex> errors_on(changeset)[:relationship_type]
      ["is invalid"]
  """
  @doc since: "0.1.0"
  @spec link_entity_account(
          BusinessEntity.t() | integer(),
          VirtualAccount.t() | integer(),
          atom(),
          map()
        ) ::
          {:ok, EntityAccount.t()} | {:error, Ecto.Changeset.t()}
  def link_entity_account(entity, account, relationship_type, attrs \\ %{})

  def link_entity_account(
        %BusinessEntity{id: entity_id},
        %VirtualAccount{id: account_id},
        type,
        attrs
      ) do
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

  @doc """
  Unlinks `entity` and `account` for `relationship_type` by setting `valid_to`
  to today. The relationship row is preserved for audit — only the active link
  is ended.

  ## Arguments

    * `entity` — `%BusinessEntity{}` or `integer()` entity id.
    * `account` — `%VirtualAccount{}` or `integer()` account id.
    * `relationship_type` — `atom()` — e.g. `:owner`.

  ## Returns

    * `{integer(), nil}` — the number of rows updated (0 or 1).

  ## Examples

      iex> Logistiki.Relationships.unlink_entity_account(acme_entity, operating_account, :owner)
      {1, nil}

      iex> Logistiki.Relationships.unlink_entity_account(acme_entity, unknown_account, :owner)
      {0, nil}
  """
  @doc since: "0.1.0"
  @spec unlink_entity_account(
          BusinessEntity.t() | integer(),
          VirtualAccount.t() | integer(),
          atom()
        ) ::
          {integer(), nil}
  def unlink_entity_account(
        %BusinessEntity{id: entity_id},
        %VirtualAccount{id: account_id},
        relationship_type
      ) do
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

  @doc """
  Lists accounts linked to `entity`, optionally filtered.

  ## Arguments

    * `entity_or_id` — `%BusinessEntity{}` or `integer()` entity id.
    * `opts` — `keyword()` of options:
        * `:relationship_type` — `atom()` — filter by type (e.g. `:owner`)
        * `:at` — `Date.t` — effective date; only relationships active on this
          date are returned. When omitted, only currently active relationships
          (`valid_to IS NULL`) are returned.
        * `:currency` — `String.t` — filter to a currency

  ## Returns

    * `[VirtualAccount.t()]` — ordered by code. Empty list if none.

  ## Examples

      iex> Logistiki.Relationships.list_accounts_for_entity(acme_entity)
      [%VirtualAccount{code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", ...}]

      iex> Logistiki.Relationships.list_accounts_for_entity(acme_entity, relationship_type: :owner)
      [%VirtualAccount{code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", ...}]

      iex> Logistiki.Relationships.list_accounts_for_entity(acme_entity, at: ~D[2026-01-01])
      []
  """
  @doc since: "0.1.0"
  @spec list_accounts_for_entity(BusinessEntity.t() | integer(), keyword()) :: [VirtualAccount.t()]
  def list_accounts_for_entity(entity_or_id, opts \\ [])

  def list_accounts_for_entity(%BusinessEntity{id: id}, opts),
    do: list_accounts_for_entity(id, opts)

  def list_accounts_for_entity(entity_id, opts)
      when is_integer(entity_id) or is_binary(entity_id) do
    direct_accounts_query(entity_id, opts)
    |> order_by([a], asc: a.code)
    |> Repo.all()
  end

  @doc """
  Lists accounts linked to `entity` or any of its descendants.

  Uses the business-entity closure table to find all descendant entity ids,
  then finds all accounts linked to any of them.

  ## Arguments

    * `entity` — `%BusinessEntity{}` — the root of the entity subtree.
    * `opts` — `keyword()` — same options as `list_accounts_for_entity/2`.

  ## Returns

    * `[VirtualAccount.t()]` — ordered by code. Empty list if none.

  ## Examples

      iex> Logistiki.Relationships.list_accounts_for_entity_tree(acme_holdings)
      [%VirtualAccount{code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:OPERATING", ...},
       %VirtualAccount{code: "LIABILITIES:CLIENT_DEPOSITS:USD:ACME:PAYROLL", ...}]
  """
  @doc since: "0.1.0"
  @spec list_accounts_for_entity_tree(BusinessEntity.t(), keyword()) :: [VirtualAccount.t()]
  def list_accounts_for_entity_tree(%BusinessEntity{} = entity, opts \\ []) do
    entity_ids = Logistiki.BusinessEntities.descendant_ids(entity)

    tree_accounts_query(entity_ids, opts)
    |> order_by([a], asc: a.code)
    |> Repo.all()
  end

  @doc """
  Lists entities linked to `account`, optionally filtered.

  ## Arguments

    * `account_or_id` — `%VirtualAccount{}` or `integer()` account id.
    * `opts` — `keyword()` of options:
        * `:relationship_type` — `atom()` — filter by type (e.g. `:owner`)
        * `:at` — `Date.t` — effective date

  ## Returns

    * `[BusinessEntity.t()]` — ordered by name. Empty list if none.

  ## Examples

      iex> Logistiki.Relationships.list_entities_for_account(operating_account)
      [%BusinessEntity{name: "Acme Holdings", ...}]

      iex> Logistiki.Relationships.list_entities_for_account(operating_account, relationship_type: :owner)
      [%BusinessEntity{name: "Acme Holdings", ...}]
  """
  @doc since: "0.1.0"
  @spec list_entities_for_account(VirtualAccount.t() | integer(), keyword()) :: [BusinessEntity.t()]
  def list_entities_for_account(account_or_id, opts \\ [])

  def list_entities_for_account(%VirtualAccount{id: id}, opts),
    do: list_entities_for_account(id, opts)

  def list_entities_for_account(account_id, opts)
      when is_integer(account_id) or is_binary(account_id) do
    direct_entities_query(account_id, opts)
    |> order_by([e], asc: e.name)
    |> Repo.all()
  end

  # Query: accounts linked directly to `entity_id`, filtered by effective date
  # and relationship type.
  defp direct_accounts_query(entity_id, opts) do
    from(a in VirtualAccount,
      join: r in EntityAccount,
      on: r.virtual_account_id == a.id,
      where: r.business_entity_id == ^entity_id,
      where: ^effective_filter(opts),
      where: ^type_filter(opts)
    )
  end

  # Query: accounts linked to any entity in `entity_ids` (used for entity-tree
  # queries).
  defp tree_accounts_query(entity_ids, opts) do
    from(a in VirtualAccount,
      join: r in EntityAccount,
      on: r.virtual_account_id == a.id,
      where: r.business_entity_id in ^entity_ids,
      where: ^effective_filter(opts),
      where: ^type_filter(opts)
    )
  end

  # Query: entities linked directly to `account_id`, filtered by effective date
  # and relationship type.
  defp direct_entities_query(account_id, opts) do
    from(e in BusinessEntity,
      join: r in EntityAccount,
      on: r.business_entity_id == e.id,
      where: r.virtual_account_id == ^account_id,
      where: ^effective_filter(opts),
      where: ^type_filter(opts)
    )
  end

  # Builds a dynamic filter for effective dating. When `:at` is given, returns
  # relationships active on that date; otherwise returns only currently active
  # relationships (valid_to IS NULL).
  defp effective_filter(opts) do
    case Keyword.get(opts, :at) do
      nil -> dynamic([_, r], is_nil(r.valid_to))
      date -> dynamic([_, r], r.valid_from <= ^date and (is_nil(r.valid_to) or r.valid_to >= ^date))
    end
  end

  # Builds a dynamic filter for relationship type.
  defp type_filter(opts) do
    case Keyword.get(opts, :relationship_type) do
      nil -> dynamic(true)
      type -> dynamic([_, r], r.relationship_type == ^Atom.to_string(type))
    end
  end
end
