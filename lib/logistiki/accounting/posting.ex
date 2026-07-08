defmodule Logistiki.Accounting.Posting do
  @moduledoc """
  A posting is a single debit or credit leg of a journal.

  Amounts are always positive; the `debit_credit` field encodes direction.
  Postings only target leaf virtual accounts. Once a journal is posted, its
  postings are immutable.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @directions ~w(debit credit)a

  schema "postings" do
    field :account_code, :string
    field :debit_credit, :string
    field :amount, :decimal
    field :currency, :string
    field :memo, :string
    field :sequence, :integer
    field :metadata, :map, default: %{}

    belongs_to :journal, Logistiki.Accounting.Journal
    belongs_to :virtual_account, Logistiki.VirtualAccounts.VirtualAccount

    timestamps(type: :utc_datetime)
  end

  def directions, do: @directions

  @doc false
  def changeset(posting, attrs) do
    posting
    |> cast(attrs, [
      :journal_id,
      :virtual_account_id,
      :account_code,
      :debit_credit,
      :amount,
      :currency,
      :memo,
      :sequence,
      :metadata
    ])
    |> validate_required([:account_code, :debit_credit, :amount, :currency, :sequence])
    |> validate_inclusion(:debit_credit, Enum.map(@directions, &Atom.to_string/1))
    |> validate_number(:amount, greater_than: 0)
    |> validate_number(:sequence, greater_than: 0)
  end

  @doc "True for a debit posting."
  def debit?(%__MODULE__{debit_credit: "debit"}), do: true
  def debit?(_), do: false

  @doc "True for a credit posting."
  def credit?(%__MODULE__{debit_credit: "credit"}), do: true
  def credit?(_), do: false

  @doc "Returns the signed amount: positive for debit, negative for credit."
  def signed_amount(%__MODULE__{amount: a, debit_credit: "debit"}), do: a
  def signed_amount(%__MODULE__{amount: a, debit_credit: "credit"}), do: Decimal.negate(a)
end
