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
  """

  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(draft validated posted reversed rejected)a

  schema "journals" do
    field :event_id, :string
    field :external_id, :string
    field :source_system, :string
    field :source_type, :string
    field :source_id, :string
    field :selected_policy, :string
    field :selected_template, :string
    field :description, :string
    field :status, :string, default: "draft"
    field :effective_date, :date
    field :posted_at, :utc_datetime
    field :reversed_at, :utc_datetime
    field :idempotency_key, :string
    field :explanation, :map
    field :metadata, :map, default: %{}

    has_many :postings, Logistiki.Accounting.Posting, on_replace: :delete

    belongs_to :reversal_of, __MODULE__, foreign_key: :reversal_of_id

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc false
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

  @doc "True when the journal is posted (and therefore immutable)."
  def posted?(%__MODULE__{status: "posted"}), do: true
  def posted?(_), do: false

  @doc "True when the journal is a reversal of another journal."
  def reversal?(%__MODULE__{reversal_of_id: id}) when not is_nil(id), do: true
  def reversal?(_), do: false
end
