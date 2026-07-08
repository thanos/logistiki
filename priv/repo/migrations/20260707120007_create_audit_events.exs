defmodule Logistiki.Repo.Migrations.CreateAuditEvents do
  use Ecto.Migration

  def change do
    create table(:audit_events) do
      add :actor_id, :string, null: true
      add :event_id, :string, null: true
      add :journal_id, references(:journals, on_delete: :nilify_all), null: true
      add :action, :string, null: false
      add :resource_type, :string, null: true
      add :resource_id, :string, null: true
      add :before, :map, null: true
      add :after, :map, null: true
      add :explanation, :map, null: true
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:audit_events, [:event_id])
    create index(:audit_events, [:journal_id])
    create index(:audit_events, [:action])
    create index(:audit_events, [:resource_type, :resource_id])
  end
end
