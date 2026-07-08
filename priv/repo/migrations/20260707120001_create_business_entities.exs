defmodule Logistiki.Repo.Migrations.CreateBusinessEntities do
  use Ecto.Migration

  def change do
    create table(:business_entities) do
      add :parent_id, references(:business_entities, on_delete: :nilify_all), null: true
      add :name, :string, null: false
      add :legal_name, :string, null: true
      add :entity_type, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :jurisdiction, :string, null: true
      add :external_id, :string, null: true
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:business_entities, [:parent_id])
    create unique_index(:business_entities, [:external_id])
    create index(:business_entities, [:entity_type])
    create index(:business_entities, [:status])

    create table(:business_entity_closure) do
      add :ancestor_id,
          references(:business_entities, on_delete: :delete_all),
          null: false

      add :descendant_id,
          references(:business_entities, on_delete: :delete_all),
          null: false

      add :depth, :integer, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:business_entity_closure, [:ancestor_id, :descendant_id, :depth])
    create index(:business_entity_closure, [:descendant_id])
    create index(:business_entity_closure, [:ancestor_id])
  end
end
