defmodule Logistiki.Repo.Migrations.CreateKnowledge do
  use Ecto.Migration

  def change do
    create table(:knowledge_programs) do
      add :name, :string, null: false
      add :version, :string, null: false
      add :status, :string, null: false, default: "active"
      add :source, :text, null: true
      add :checksum, :string, null: true
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:knowledge_programs, [:name, :version])

    create table(:knowledge_facts) do
      add :program_id, references(:knowledge_programs, on_delete: :delete_all), null: false
      add :predicate, :string, null: false
      add :arguments, :map, null: false, default: %{}
      add :source_type, :string, null: true
      add :source_id, :string, null: true
      add :valid_from, :utc_datetime, null: true
      add :valid_to, :utc_datetime, null: true
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:knowledge_facts, [:program_id])
    create index(:knowledge_facts, [:predicate])
  end
end
