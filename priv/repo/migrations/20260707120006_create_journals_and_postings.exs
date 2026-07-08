defmodule Logistiki.Repo.Migrations.CreateJournalsAndPostings do
  use Ecto.Migration

  def change do
    create table(:journals) do
      add :event_id, :string, null: true
      add :external_id, :string, null: true
      add :source_system, :string, null: true
      add :source_type, :string, null: true
      add :source_id, :string, null: true
      add :selected_policy, :string, null: true
      add :selected_template, :string, null: true
      add :description, :string, null: true
      add :status, :string, null: false, default: "draft"
      add :effective_date, :date, null: true
      add :posted_at, :utc_datetime, null: true
      add :reversed_at, :utc_datetime, null: true
      add :reversal_of_id, references(:journals, on_delete: :nilify_all), null: true
      add :idempotency_key, :string, null: true
      add :explanation, :map, null: true
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:journals, [:event_id])
    create index(:journals, [:status])
    create unique_index(:journals, [:idempotency_key])
    create index(:journals, [:effective_date])
    create index(:journals, [:reversal_of_id])

    create table(:postings) do
      add :journal_id, references(:journals, on_delete: :delete_all), null: false
      add :virtual_account_id, references(:virtual_accounts, on_delete: :nilify_all), null: true
      add :account_code, :string, null: false
      add :debit_credit, :string, null: false
      add :amount, :decimal, precision: 20, scale: 4, null: false
      add :currency, :string, null: false
      add :memo, :string, null: true
      add :sequence, :integer, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:postings, [:journal_id])
    create index(:postings, [:virtual_account_id])
    create index(:postings, [:account_code])
    create index(:postings, [:currency])
    create index(:postings, [:debit_credit])
  end
end
