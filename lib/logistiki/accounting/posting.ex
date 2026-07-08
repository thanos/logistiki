defmodule Logistiki.Accounting.Posting do
  @moduledoc """
  A posting is a single debit or credit leg of a journal.

  Amounts are always positive; the `debit_credit` field encodes direction.
  Postings only target leaf virtual accounts. Once a journal is posted, its
  postings are immutable.

  ## Fields

    * `id` — `integer()` — primary key
    * `journal_id` — `integer()` — FK to `journals`
    * `virtual_account_id` — `integer() | nil` — FK to `virtual_accounts`
    * `account_code` — `String.t()` — denormalized for audit readability (e.g.
      `"ASSETS:CASH:USD:NOSTRO"`)
    * `debit_credit` — `String.t()` — `"debit"` or `"credit"`
    * `amount` — `Decimal.t()` — always positive (e.g. `Decimal.new("1000.00")`)
    * `currency` — `String.t()` — e.g. `"USD"`
    * `memo` — `String.t() | nil`
    * `sequence` — `integer()` — ordering within the journal (1-based)
    * `metadata` — `map()` — includes the symbolic `role` (e.g.
      `%{"role" => "cash_account"}`)
    * `inserted_at` / `updated_at` — `DateTime.t()`

  ## Rules

    * amount is positive; direction encodes sign
    * `debit_credit` is `debit` or `credit`
    * the posting account must be a leaf, active, posting-allowed account
    * the journal must balance per currency
    * postings are immutable once the journal is posted
    * `account_code` is denormalized for audit readability but
      `virtual_account_id` remains canonical

  ## Example

      %Logistiki.Accounting.Posting{
        id: 1,
        journal_id: 1,
        virtual_account_id: 10,
        account_code: "ASSETS:CASH:USD:NOSTRO",
        debit_credit: "debit",
        amount: Decimal.new("1000.00"),
        currency: "USD",
        sequence: 1,
        metadata: %{"role" => "cash_account"}
      }
  """

  use Ecto.Schema

  import Ecto.Changeset

  @directions ~w(debit credit)a

  schema "postings" do
    # Account code (denormalized for audit readability). Example: `\"ASSETS:CASH:USD:NOSTRO\"`
    field(:account_code, :string)
    # Direction: `\"debit\"` or `\"credit\"`. Example: `\"debit\"`
    field(:debit_credit, :string)
    # Amount (always positive). Example: `Decimal.new(\"1000.00\")`
    field(:amount, :decimal)
    # Currency code. Example: `\"USD\"`
    field(:currency, :string)
    # Optional memo/note. Example: `\"wire deposit\"`
    field(:memo, :string)
    # Sequence within the journal (1-based). Example: `1`
    field(:sequence, :integer)

    # Metadata including the symbolic role. Default: `%{}`. Example: `%{\"role\" => \"cash_account\"}`
    field(:metadata, :map, default: %{})

    belongs_to(:journal, Logistiki.Accounting.Journal)
    belongs_to(:virtual_account, Logistiki.VirtualAccounts.VirtualAccount)

    timestamps(type: :utc_datetime)
  end

  @typedoc """
  The `Posting` struct type — a single debit or credit leg of a journal.

  ## Fields

    * `id` — `integer() | nil` — primary key (e.g. `1`)
    * `journal_id` — `integer() | nil` — FK to `journals` (e.g. `1`)
    * `virtual_account_id` — `integer() | nil` — FK to `virtual_accounts` (e.g. `10`)
    * `account_code` — `String.t() | nil` — denormalized (e.g. `"ASSETS:CASH:USD:NOSTRO"`)
    * `debit_credit` — `String.t() | nil` — `"debit"` or `"credit"`
    * `amount` — `Decimal.t() | nil` — always positive (e.g. `Decimal.new("1000.00")`)
    * `currency` — `String.t() | nil` — e.g. `"USD"`
    * `memo` — `String.t() | nil` — optional memo
    * `sequence` — `integer() | nil` — ordering within the journal
    * `metadata` — `map() | nil` — includes the symbolic role
    * `inserted_at` — `DateTime.t() | nil`
    * `updated_at` — `DateTime.t() | nil`

  ## Example

      %Logistiki.Accounting.Posting{
        id: 1, journal_id: 1, virtual_account_id: 10,
        account_code: "ASSETS:CASH:USD:NOSTRO", debit_credit: "debit",
        amount: Decimal.new("1000.00"), currency: "USD", sequence: 1
      }
  """

  @type t :: %__MODULE__{
          id: integer() | nil,
          journal_id: integer() | nil,
          virtual_account_id: integer() | nil,
          account_code: String.t() | nil,
          debit_credit: String.t() | nil,
          amount: Decimal.t() | nil,
          currency: String.t() | nil,
          memo: String.t() | nil,
          sequence: integer() | nil,
          metadata: map() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Returns the list of allowed posting directions as atoms.

  ## Returns

    * `[atom()]` — `[:debit, :credit]`

  ## Examples

      iex> Logistiki.Accounting.Posting.directions()
      [:debit, :credit]
  """
  @doc since: "0.1.0"
  @spec directions() :: [atom(), ...]
  def directions, do: @directions

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
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

  @doc """
  True for a debit posting.

  ## Arguments

    * `posting` — `%__MODULE__{}` or any term.

  ## Returns

    * `boolean()` — `true` when `debit_credit == "debit"`.

  ## Examples

      iex> Logistiki.Accounting.Posting.debit?(%Logistiki.Accounting.Posting{debit_credit: "debit"})
      true
      iex> Logistiki.Accounting.Posting.debit?(%Logistiki.Accounting.Posting{debit_credit: "credit"})
      false
  """
  @doc since: "0.1.0"
  @spec debit?(t()) :: boolean()
  def debit?(%__MODULE__{debit_credit: "debit"}), do: true
  def debit?(_), do: false

  @doc """
  True for a credit posting.

  ## Arguments

    * `posting` — `%__MODULE__{}` or any term.

  ## Returns

    * `boolean()` — `true` when `debit_credit == "credit"`.

  ## Examples

      iex> Logistiki.Accounting.Posting.credit?(%Logistiki.Accounting.Posting{debit_credit: "credit"})
      true
  """
  @doc since: "0.1.0"
  @spec credit?(t()) :: boolean()
  def credit?(%__MODULE__{debit_credit: "credit"}), do: true
  def credit?(_), do: false

  @doc """
  Returns the signed amount: positive for debit, negative for credit.

  ## Arguments

    * `posting` — `%__MODULE__{}`.

  ## Returns

    * `Decimal.t()` — `amount` for debit, `-amount` for credit.

  ## Examples

      iex> Logistiki.Accounting.Posting.signed_amount(%Logistiki.Accounting.Posting{amount: Decimal.new("100"), debit_credit: "debit"})
      Decimal.new("100")
      iex> Logistiki.Accounting.Posting.signed_amount(%Logistiki.Accounting.Posting{amount: Decimal.new("100"), debit_credit: "credit"})
      Decimal.new("-100")
  """
  @doc since: "0.1.0"
  @spec signed_amount(t()) :: Decimal.t()
  def signed_amount(%__MODULE__{amount: a, debit_credit: "debit"}), do: a
  def signed_amount(%__MODULE__{amount: a, debit_credit: "credit"}), do: Decimal.negate(a)
end
