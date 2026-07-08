defmodule Logistiki.Repo.Migrations.CreateBusinessEvents do
  use Ecto.Migration

  def change do
    create table(:business_events) do
      add :event_type, :string, null: false
      add :source_system, :string, null: true
      add :source_id, :string, null: true
      add :actor_id, :string, null: true
      add :occurred_at, :utc_datetime, null: true
      add :effective_date, :date, null: true
      add :payload, :map, null: false, default: %{}
      add :normalized_payload, :map, null: true
      add :status, :string, null: false, default: "received"
      add :explanation, :map, null: true
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:business_events, [:event_type])
    create index(:business_events, [:status])
    create index(:business_events, [:source_system, :source_id])
    create index(:business_events, [:effective_date])
  end
end
