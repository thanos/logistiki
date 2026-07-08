defmodule Logistiki.Accounting.Journal do
  @moduledoc """
  A journal is an internal accounting artifact created by the runtime from a
  business event. Journals are not the main application-facing API; applications
  publish business events.

  ## Statuses

    * `draft` — built but not yet posted
    * `validated` — passed invariant validation
    * `posted` — immutable, persisted, executed by the ledger backend
    * `reversed` — fully reversed by a later reversal journal
    * `rejected` — preserved for audit

  ## Fields

    * `id` — `integer()` — primary key
    * `event_id` — `String.t() | nil` — the originating business event id
    * `external_id` — `String.t() | nil`
    * `source_system` / `source_type` / `source_id` — `String.t() | nil` — provenance
    * `selected_policy` — `String.t() | nil` — e.g. `"cash_deposit"`
    * `selected_template` — `String.t() | nil`
    * `description` — `String.t() | nil`
    * `status` — `String.t()` — one of `statuses/0` (default `"draft"`)
    * `effective_date` — `Date.t() | nil`
    * `posted_at` — `DateTime.t() | nil` — set when posted
    * `reversed_at` — `DateTime.t() | nil` — set when reversed
    * `reversal_of_id` — `integer() | nil` — self-reference for reversals
    * `idempotency_key` — `String.t() | nil` — unique; prevents duplicate posting
    * `explanation` — `map() | nil` — full knowledge-layer explanation
    * `metadata` — `map()`
    * `postings` — `[Posting.t()]` — has_many association
    * `inserted_at` / `updated_at` — `DateTime.t()`

  ## Rules

    * posted journals are immutable
    * rejected journals are preserved for audit
    * reversals create a new journal that exactly negates the original postings
    * the idempotency key prevents duplicate posting

  ## Example

      %Logistiki.Accounting.Journal{
        id: 1,
        event_id: "evt_001",
        selected_policy: "cash_deposit",
        status: "posted",
        effective_date: ~D[2026-07-07],
        posted_at: ~U[2026-07-07 12:00:00Z],
        idempotency_key: "evt:evt_001:policy:cash_deposit"
      }
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(draft validated posted reversed rejected)a

  schema "journals" do
    # Originating business event id. Example: `\"evt_001\"`
    field(:event_id, :string)
    # External reference id. Example: `\"ext_123\"`
    field(:external_id, :string)
    # Source system that produced the event. Example: `\"bank_core\"`
    field(:source_system, :string)
    # Source event type. Example: `\"deposit_received\"`
    field(:source_type, :string)
    # Source-system event id. Example: `\"wire_123\"`
    field(:source_id, :string)
    # Selected accounting policy (for replay/audit). Example: `\"cash_deposit\"`
    field(:selected_policy, :string)
    # Selected posting template (for replay/audit). Example: `\"cash_deposit\"`
    field(:selected_template, :string)
    # Human-readable description. Example: `\"deposit_received via cash_deposit\"`
    field(:description, :string)
    # Journal status, one of `statuses/0`. Default: `\"draft\"`. Example: `\"posted\"`
    field(:status, :string, default: "draft")
    # Accounting effective date. Example: `~D[2026-07-07]`
    field(:effective_date, :date)
    # When the journal was posted. Example: `~U[2026-07-07 12:00:00Z]`
    field(:posted_at, :utc_datetime)
    # When the journal was reversed. Example: `~U[2026-07-07 14:00:00Z]`
    field(:reversed_at, :utc_datetime)

    # Unique idempotency key preventing duplicate posting. Example: `\"evt:evt_001:policy:cash_deposit\"`
    field(:idempotency_key, :string)
    # Full pipeline explanation map. Example: `%{policy: :cash_deposit, account_roles: %{...}}`
    field(:explanation, :map)
    # Extensible metadata. Default: `%{}`. Example: `%{\"actor_id\" => \"user_1\"}`
    field(:metadata, :map, default: %{})

    has_many(:postings, Logistiki.Accounting.Posting, on_replace: :delete)
    belongs_to(:reversal_of, __MODULE__, foreign_key: :reversal_of_id)

    timestamps(type: :utc_datetime)
  end

  @typedoc """
  The `Journal` struct type — an internal accounting artifact created by the
  runtime from a business event.

  ## Fields

    * `id` — `integer() | nil` — primary key (e.g. `1`)
    * `event_id` — `String.t() | nil` — originating event id (e.g. `"evt_001"`)
    * `external_id` — `String.t() | nil` — external reference
    * `source_system` — `String.t() | nil` — e.g. `"bank_core"`
    * `source_type` — `String.t() | nil` — e.g. `"deposit_received"`
    * `source_id` — `String.t() | nil` — e.g. `"wire_123"`
    * `selected_policy` — `String.t() | nil` — e.g. `"cash_deposit"`
    * `selected_template` — `String.t() | nil` — e.g. `"cash_deposit"`
    * `description` — `String.t() | nil` — e.g. `"deposit_received via cash_deposit"`
    * `status` — `String.t() | nil` — e.g. `"draft"`, `"posted"`, `"reversed"`
    * `effective_date` — `Date.t() | nil` — e.g. `~D[2026-07-07]`
    * `posted_at` — `DateTime.t() | nil` — e.g. `~U[2026-07-07 12:00:00Z]`
    * `reversed_at` — `DateTime.t() | nil`
    * `reversal_of_id` — `integer() | nil` — self-reference for reversals
    * `idempotency_key` — `String.t() | nil` — unique duplicate-prevention key
    * `explanation` — `map() | nil` — full pipeline explanation
    * `metadata` — `map() | nil` — extensible metadata
    * `postings` — `[Posting.t()] | Ecto.Association.NotLoaded.t()` — postings
    * `inserted_at` — `DateTime.t() | nil`
    * `updated_at` — `DateTime.t() | nil`

  ## Example

      %Logistiki.Accounting.Journal{
        id: 1, event_id: "evt_001", selected_policy: "cash_deposit",
        status: "posted", effective_date: ~D[2026-07-07]
      }
  """

  @type t :: %__MODULE__{
          id: integer() | nil,
          event_id: String.t() | nil,
          external_id: String.t() | nil,
          source_system: String.t() | nil,
          source_type: String.t() | nil,
          source_id: String.t() | nil,
          selected_policy: String.t() | nil,
          selected_template: String.t() | nil,
          description: String.t() | nil,
          status: String.t() | nil,
          effective_date: Date.t() | nil,
          posted_at: DateTime.t() | nil,
          reversed_at: DateTime.t() | nil,
          reversal_of_id: integer() | nil,
          idempotency_key: String.t() | nil,
          explanation: map() | nil,
          metadata: map() | nil,
          postings: [Logistiki.Accounting.Posting.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Returns the list of allowed journal statuses as atoms.

  ## Returns

    * `[atom()]` — `[:draft, :validated, :posted, :reversed, :rejected]`

  ## Examples

      iex> :posted in Logistiki.Accounting.Journal.statuses()
      true
  """
  @doc since: "0.1.0"
  @spec statuses() :: [atom(), ...]
  def statuses, do: @statuses

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(journal, attrs) do
    journal
    |> cast(attrs, [
      :event_id,
      :external_id,
      :source_system,
      :source_type,
      :source_id,
      :selected_policy,
      :selected_template,
      :description,
      :status,
      :effective_date,
      :posted_at,
      :reversed_at,
      :reversal_of_id,
      :idempotency_key,
      :explanation,
      :metadata
    ])
    |> validate_required([:status])
    |> validate_inclusion(:status, Enum.map(@statuses, &Atom.to_string/1))
    |> unique_constraint(:idempotency_key)
  end

  @doc """
  True when the journal is posted (and therefore immutable).

  ## Arguments

    * `journal` — `%__MODULE__{}` or any term.

  ## Returns

    * `boolean()` — `true` only when `status == "posted"`.

  ## Examples

      iex> Logistiki.Accounting.Journal.posted?(%Logistiki.Accounting.Journal{status: "posted"})
      true
      iex> Logistiki.Accounting.Journal.posted?(%Logistiki.Accounting.Journal{status: "draft"})
      false
  """
  @doc since: "0.1.0"
  @spec posted?(t()) :: boolean()
  def posted?(%__MODULE__{status: "posted"}), do: true
  def posted?(_), do: false

  @doc """
  True when the journal is a reversal of another journal.

  ## Arguments

    * `journal` — `%__MODULE__{}` or any term.

  ## Returns

    * `boolean()` — `true` when `reversal_of_id` is not nil.

  ## Examples

      iex> Logistiki.Accounting.Journal.reversal?(%Logistiki.Accounting.Journal{reversal_of_id: 5})
      true
      iex> Logistiki.Accounting.Journal.reversal?(%Logistiki.Accounting.Journal{reversal_of_id: nil})
      false
  """
  @doc since: "0.1.0"
  @spec reversal?(t()) :: boolean()
  def reversal?(%__MODULE__{reversal_of_id: id}) when not is_nil(id), do: true
  def reversal?(_), do: false
end
