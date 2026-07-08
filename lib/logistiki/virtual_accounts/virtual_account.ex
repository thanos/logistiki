defmodule Logistiki.VirtualAccounts.VirtualAccount do
  @moduledoc """
  A hierarchical accounting account. Virtual accounts are not balances; balances
  are derived from postings. Parent accounts aggregate children.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @account_types ~w(asset liability equity income expense client settlement suspense fee tax clearing)a
  @normal_balances ~w(debit credit)a
  @statuses ~w(active inactive frozen closed)a

  schema "virtual_accounts" do
    field :code, :string
    field :name, :string
    field :account_type, :string
    field :currency, :string
    field :status, :string, default: "active"
    field :posting_allowed, :boolean, default: false
    field :normal_balance, :string
    field :external_id, :string
    field :metadata, :map, default: %{}

    belongs_to :parent, __MODULE__, foreign_key: :parent_id

    has_many :children, __MODULE__, foreign_key: :parent_id

    timestamps(type: :utc_datetime)
  end

  def account_types, do: @account_types
  def normal_balances, do: @normal_balances
  def statuses, do: @statuses

  @doc false
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

  defp validate_normal_balance(changeset) do
    values = Enum.map(@normal_balances, &Atom.to_string/1)

    case get_field(changeset, :normal_balance) do
      nil -> changeset
      value ->
        if Enum.member?(values, value) do
          changeset
        else
          add_error(changeset, :normal_balance, "must be one of #{inspect(values)}", value: value)
        end
    end
  end

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
