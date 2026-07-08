defmodule Logistiki.Repo.Migrations.CreateEntityAccounts do
  use Ecto.Migration

  def change do
    create table(:entity_accounts) do
      add :business_entity_id,
          references(:business_entities, on_delete: :delete_all),
          null: false

      add :virtual_account_id,
          references(:virtual_accounts, on_delete: :delete_all),
          null: false

      add :relationship_type, :string, null: false
      add :valid_from, :date, null: false
      add :valid_to, :date, null: true
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:entity_accounts,
             [:business_entity_id, :virtual_account_id, :relationship_type],
             name: :entity_accounts_unique_link
           )

    create index(:entity_accounts, [:business_entity_id])
    create index(:entity_accounts, [:virtual_account_id])
    create index(:entity_accounts, [:relationship_type])
    create index(:entity_accounts, [:valid_from])
    create index(:entity_accounts, [:valid_to])
  end
end
