defmodule Logistiki.VirtualAccounts.VirtualAccount do
  @moduledoc """
  A hierarchical accounting account. Virtual accounts are not balances; balances
  are derived from postings. Parent accounts aggregate children.

  ## Fields

    * `id` — `integer()` — primary key (e.g. `10`)
    * `parent_id` — `integer() | nil` — self-reference; `nil` for roots (e.g. `9` or `nil`)
    * `code` — `String.t()` — unique, stable, human-readable (colon-separated, e.g. `"ASSETS:CASH:USD:NOSTRO"`)
    * `name` — `String.t()` — display name (e.g. `"Nostro USD"`)
    * `account_type` — `String.t()` — one of `account_types/0` (e.g. `"asset"`, `"liability"`, `"client"`)
    * `currency` — `String.t() | nil` — required for posting accounts; `nil` for aggregation accounts (e.g. `"USD"` or `nil`)
    * `status` — `String.t()` — one of `statuses/0` (default `"active"`, e.g. `"frozen"`)
    * `posting_allowed` — `boolean()` — only leaf accounts may allow postings (default `false`)
    * `normal_balance` — `String.t() | nil` — `"debit"` or `"credit"` (e.g. `"debit"`)
    * `external_id` — `String.t() | nil` — unique external reference (e.g. `"core_001"`)
    * `metadata` — `map()` — extensible key/value store (default `%{}`, e.g. `%{"iban" => "GB29..."}`)
    * `inserted_at` — `DateTime.t() | nil` — set by Ecto (e.g. `~U[2026-07-07 12:00:00Z]`)
    * `updated_at` — `DateTime.t() | nil` — set by Ecto

  ## Associations

    * `parent` — `belongs_to` `__MODULE__` — the parent account (via `parent_id`)
    * `children` — `has_many` `__MODULE__` — direct child accounts

  ## Example

      %Logistiki.VirtualAccounts.VirtualAccount{
        id: 10,
        parent_id: 9,
        code: "ASSETS:CASH:USD:NOSTRO",
        name: "Nostro USD",
        account_type: "asset",
        currency: "USD",
        posting_allowed: true,
        normal_balance: "debit",
        status: "active"
      }
  """

  use Ecto.Schema

  import Ecto.Changeset

  @account_types ~w(asset liability equity income expense client settlement suspense fee tax clearing)a
  @normal_balances ~w(debit credit)a
  @statuses ~w(active inactive frozen closed)a

  schema "virtual_accounts" do
    # Unique, stable, human-readable account code (colon-separated). Example: `\"ASSETS:CASH:USD:NOSTRO\"`
    field(:code, :string)
    # Display name of the account. Example: `\"Nostro USD\"`
    field(:name, :string)
    # Account type, one of `account_types/0`. Example: `\"asset\"`, `\"liability\"`, `\"client\"`
    field(:account_type, :string)

    # Currency code; required for posting accounts, nil for aggregation accounts. Example: `\"USD\"` or `nil`
    field(:currency, :string)
    # Account status, one of `statuses/0`. Default: `\"active\"`. Example: `\"frozen\"`
    field(:status, :string, default: "active")
    # Whether postings may target this account (only leaf accounts). Default: `false`.
    field(:posting_allowed, :boolean, default: false)
    # Normal balance direction: `\"debit\"` or `\"credit\"`. Example: `\"debit\"`
    field(:normal_balance, :string)
    # Unique external reference. Example: `\"core_001\"`
    field(:external_id, :string)
    # Extensible key/value metadata. Default: `%{}`. Example: `%{\"iban\" => \"GB29...\"}`
    field(:metadata, :map, default: %{})

    belongs_to(:parent, __MODULE__, foreign_key: :parent_id)
    has_many(:children, __MODULE__, foreign_key: :parent_id)

    timestamps(type: :utc_datetime)
  end

  @typedoc """
  The `VirtualAccount` struct type.

  Represents a hierarchical accounting account. Balances are derived from
  postings — the account itself is not a balance.

  ## Fields

    * `id` — `integer() | nil` — primary key (e.g. `10`)
    * `parent_id` — `integer() | nil` — parent account id; `nil` for roots
    * `code` — `String.t() | nil` — unique code (e.g. `"ASSETS:CASH:USD:NOSTRO"`)
    * `name` — `String.t() | nil` — display name (e.g. `"Nostro USD"`)
    * `account_type` — `String.t() | nil` — e.g. `"asset"`, `"client"`
    * `currency` — `String.t() | nil` — e.g. `"USD"` or `nil` for aggregation accounts
    * `status` — `String.t() | nil` — e.g. `"active"`, `"frozen"`
    * `posting_allowed` — `boolean() | nil` — whether postings target this account
    * `normal_balance` — `String.t() | nil` — `"debit"` or `"credit"`
    * `external_id` — `String.t() | nil` — unique external reference
    * `metadata` — `map() | nil` — extensible metadata
    * `inserted_at` — `DateTime.t() | nil`
    * `updated_at` — `DateTime.t() | nil`

  ## Example

      %Logistiki.VirtualAccounts.VirtualAccount{
        id: 10, parent_id: 9, code: "ASSETS:CASH:USD:NOSTRO",
        name: "Nostro USD", account_type: "asset", currency: "USD",
        posting_allowed: true, normal_balance: "debit", status: "active"
      }
  """

  @type t :: %__MODULE__{
          id: integer() | nil,
          parent_id: integer() | nil,
          code: String.t() | nil,
          name: String.t() | nil,
          account_type: String.t() | nil,
          currency: String.t() | nil,
          status: String.t() | nil,
          posting_allowed: boolean() | nil,
          normal_balance: String.t() | nil,
          external_id: String.t() | nil,
          metadata: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Returns the list of allowed account types as atoms.

  ## Returns

    * `[atom()]` — `[:asset, :liability, :equity, :income, :expense,
      :client, :settlement, :suspense, :fee, :tax, :clearing]`

  ## Examples

      iex> :asset in Logistiki.VirtualAccounts.VirtualAccount.account_types()
      true
  """
  @doc since: "0.1.0"
  @spec account_types() :: [atom(), ...]
  def account_types, do: @account_types

  @doc """
  Returns the list of allowed normal-balance values as atoms.

  ## Returns

    * `[atom()]` — `[:debit, :credit]`

  ## Examples

      iex> Logistiki.VirtualAccounts.VirtualAccount.normal_balances()
      [:debit, :credit]
  """
  @doc since: "0.1.0"
  @spec normal_balances() :: [atom(), ...]
  def normal_balances, do: @normal_balances

  @doc """
  Returns the list of allowed account statuses as atoms.

  ## Returns

    * `[atom()]` — `[:active, :inactive, :frozen, :closed]`

  ## Examples

      iex> Logistiki.VirtualAccounts.VirtualAccount.statuses()
      [:active, :inactive, :frozen, :closed]
  """
  @doc since: "0.1.0"
  @spec statuses() :: [atom(), ...]
  def statuses, do: @statuses

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(account, attrs) do
    account
    |> cast(attrs, [
      :code,
      :name,
      :account_type,
      :currency,
      :status,
      :posting_allowed,
      :normal_balance,
      :external_id,
      :parent_id,
      :metadata
    ])
    |> validate_required([:code, :name, :account_type, :status])
    |> validate_inclusion(:account_type, Enum.map(@account_types, &Atom.to_string/1))
    |> validate_inclusion(:status, Enum.map(@statuses, &Atom.to_string/1))
    |> validate_normal_balance()
    |> unique_constraint(:code)
    |> validate_posting_account()
  end

  # Validates that `normal_balance` is one of `@normal_balances` when present.
  defp validate_normal_balance(changeset) do
    values = Enum.map(@normal_balances, &Atom.to_string/1)

    case get_field(changeset, :normal_balance) do
      nil ->
        changeset

      value ->
        if Enum.member?(values, value) do
          changeset
        else
          add_error(changeset, :normal_balance, "must be one of #{inspect(values)}", value: value)
        end
    end
  end

  # Validates that a posting-allowed account has a currency. Only posting
  # accounts (leaf, active, posting_allowed) need a currency; aggregation
  # accounts may have nil.
  defp validate_posting_account(changeset) do
    posting_allowed? = get_field(changeset, :posting_allowed)
    currency = get_field(changeset, :currency)

    if posting_allowed? and is_nil(currency) do
      add_error(changeset, :currency, "can't be blank when posting is allowed")
    else
      changeset
    end
  end
end
