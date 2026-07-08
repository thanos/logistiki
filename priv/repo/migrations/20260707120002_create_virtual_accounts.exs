defmodule Logistiki.Repo.Migrations.CreateVirtualAccounts do
  use Ecto.Migration

  def change do
    create table(:virtual_accounts) do
      add :parent_id, references(:virtual_accounts, on_delete: :nilify_all), null: true
      add :code, :string, null: false
      add :name, :string, null: false
      add :account_type, :string, null: false
      add :currency, :string, null: true
      add :status, :string, null: false, default: "active"
      add :posting_allowed, :boolean, null: false, default: false
      add :normal_balance, :string, null: true
      add :external_id, :string, null: true
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:virtual_accounts, [:code])
    create index(:virtual_accounts, [:parent_id])
    create index(:virtual_accounts, [:account_type])
    create index(:virtual_accounts, [:currency])
    create index(:virtual_accounts, [:status])

    create table(:virtual_account_closure) do
      add :ancestor_id,
          references(:virtual_accounts, on_delete: :delete_all),
          null: false

      add :descendant_id,
          references(:virtual_accounts, on_delete: :delete_all),
          null: false

      add :depth, :integer, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:virtual_account_closure, [:ancestor_id, :descendant_id, :depth])
    create index(:virtual_account_closure, [:descendant_id])
    create index(:virtual_account_closure, [:ancestor_id])
  end
end
