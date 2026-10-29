defmodule Logistiki.Repo.Migrations.V011Durability do
  @moduledoc false
  use Ecto.Migration

  def up do
    alter table(:business_events) do
      add :external_event_id, :string, null: true
      add :payload_fingerprint, :string, null: true
    end

    create unique_index(:business_events, [:external_event_id],
             name: :business_events_external_event_id_index,
             where: "external_event_id IS NOT NULL"
           )

    create unique_index(:business_events, [:source_system, :source_id],
             name: :business_events_source_unique_index,
             where: "source_system IS NOT NULL AND source_id IS NOT NULL"
           )

    create index(:business_events, [:payload_fingerprint])

    create unique_index(:journals, [:reversal_of_id],
             name: :journals_reversal_of_id_unique_index,
             where: "reversal_of_id IS NOT NULL"
           )

    create unique_index(:postings, [:journal_id, :sequence],
             name: :postings_journal_id_sequence_index
           )

    create table(:audit_pending) do
      add :event_id, :string, null: true
      add :journal_id, :bigint, null: true
      add :action, :string, null: false
      add :resource_type, :string, null: true
      add :resource_id, :string, null: true
      add :explanation, :map, null: true
      add :metadata, :map, null: false, default: %{}
      add :status, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :last_error, :string, null: true

      timestamps(type: :utc_datetime)
    end

    create index(:audit_pending, [:status])
    create index(:audit_pending, [:event_id])

    create_immutability_triggers()
  end

  def down do
    drop_immutability_triggers()

    drop table(:audit_pending)

    drop_if_exists index(:postings, [:journal_id, :sequence],
                     name: :postings_journal_id_sequence_index
                   )

    drop_if_exists index(:journals, [:reversal_of_id],
                     name: :journals_reversal_of_id_unique_index
                   )

    drop_if_exists index(:business_events, [:payload_fingerprint])

    drop_if_exists index(:business_events, [:source_system, :source_id],
                     name: :business_events_source_unique_index
                   )

    drop_if_exists index(:business_events, [:external_event_id],
                     name: :business_events_external_event_id_index
                   )

    alter table(:business_events) do
      remove :payload_fingerprint
      remove :external_event_id
    end
  end

  defp create_immutability_triggers do
    case repo().__adapter__() do
      Ecto.Adapters.Postgres ->
        execute("""
        CREATE OR REPLACE FUNCTION logistiki_forbid_posting_mutation()
        RETURNS trigger AS $$
        BEGIN
          RAISE EXCEPTION 'logistiki: postings are immutable after insert';
        END;
        $$ LANGUAGE plpgsql;
        """)

        execute("""
        CREATE TRIGGER postings_immutable_update
          BEFORE UPDATE ON postings
          FOR EACH ROW EXECUTE PROCEDURE logistiki_forbid_posting_mutation();
        """)

        execute("""
        CREATE TRIGGER postings_immutable_delete
          BEFORE DELETE ON postings
          FOR EACH ROW EXECUTE PROCEDURE logistiki_forbid_posting_mutation();
        """)

        execute("""
        CREATE OR REPLACE FUNCTION logistiki_journal_immutability()
        RETURNS trigger AS $$
        BEGIN
          IF TG_OP = 'DELETE' THEN
            RAISE EXCEPTION 'logistiki: journals cannot be deleted';
          END IF;

          IF OLD.status IN ('posted', 'reversed') THEN
            IF NEW.status = OLD.status
               AND NEW.reversed_at IS NOT DISTINCT FROM OLD.reversed_at
               AND NEW.posted_at IS NOT DISTINCT FROM OLD.posted_at
               AND NEW.event_id IS NOT DISTINCT FROM OLD.event_id
               AND NEW.idempotency_key IS NOT DISTINCT FROM OLD.idempotency_key
               AND NEW.reversal_of_id IS NOT DISTINCT FROM OLD.reversal_of_id
               AND NEW.selected_policy IS NOT DISTINCT FROM OLD.selected_policy
               AND NEW.selected_template IS NOT DISTINCT FROM OLD.selected_template
               AND NEW.description IS NOT DISTINCT FROM OLD.description
               AND NEW.effective_date IS NOT DISTINCT FROM OLD.effective_date
               AND NEW.source_system IS NOT DISTINCT FROM OLD.source_system
               AND NEW.source_id IS NOT DISTINCT FROM OLD.source_id
               AND NEW.source_type IS NOT DISTINCT FROM OLD.source_type
               AND NEW.external_id IS NOT DISTINCT FROM OLD.external_id
               AND NEW.explanation IS NOT DISTINCT FROM OLD.explanation
               AND NEW.metadata IS NOT DISTINCT FROM OLD.metadata THEN
              RETURN NEW;
            END IF;

            IF OLD.status = 'posted'
               AND NEW.status = 'reversed'
               AND NEW.reversed_at IS NOT NULL
               AND NEW.posted_at IS NOT DISTINCT FROM OLD.posted_at
               AND NEW.event_id IS NOT DISTINCT FROM OLD.event_id
               AND NEW.idempotency_key IS NOT DISTINCT FROM OLD.idempotency_key
               AND NEW.reversal_of_id IS NOT DISTINCT FROM OLD.reversal_of_id THEN
              RETURN NEW;
            END IF;

            RAISE EXCEPTION 'logistiki: posted/reversed journals are immutable except posted→reversed';
          END IF;

          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        """)

        execute("""
        CREATE TRIGGER journals_immutability
          BEFORE UPDATE OR DELETE ON journals
          FOR EACH ROW EXECUTE PROCEDURE logistiki_journal_immutability();
        """)

      Ecto.Adapters.SQLite3 ->
        execute("""
        CREATE TRIGGER postings_immutable_update
          BEFORE UPDATE ON postings
          BEGIN
            SELECT RAISE(ABORT, 'logistiki: postings are immutable after insert');
          END;
        """)

        execute("""
        CREATE TRIGGER postings_immutable_delete
          BEFORE DELETE ON postings
          BEGIN
            SELECT RAISE(ABORT, 'logistiki: postings are immutable after insert');
          END;
        """)

        execute("""
        CREATE TRIGGER journals_immutable_delete
          BEFORE DELETE ON journals
          BEGIN
            SELECT RAISE(ABORT, 'logistiki: journals cannot be deleted');
          END;
        """)

        execute("""
        CREATE TRIGGER journals_immutability_update
          BEFORE UPDATE ON journals
          FOR EACH ROW
          WHEN OLD.status IN ('posted', 'reversed')
           AND NOT (
             OLD.status = 'posted'
             AND NEW.status = 'reversed'
             AND NEW.reversed_at IS NOT NULL
           )
          BEGIN
            SELECT RAISE(ABORT, 'logistiki: posted/reversed journals are immutable except posted→reversed');
          END;
        """)

      _ ->
        :ok
    end
  end

  defp drop_immutability_triggers do
    case repo().__adapter__() do
      Ecto.Adapters.Postgres ->
        execute("DROP TRIGGER IF EXISTS journals_immutability ON journals")
        execute("DROP TRIGGER IF EXISTS postings_immutable_delete ON postings")
        execute("DROP TRIGGER IF EXISTS postings_immutable_update ON postings")
        execute("DROP FUNCTION IF EXISTS logistiki_journal_immutability()")
        execute("DROP FUNCTION IF EXISTS logistiki_forbid_posting_mutation()")

      Ecto.Adapters.SQLite3 ->
        execute("DROP TRIGGER IF EXISTS journals_immutability_update")
        execute("DROP TRIGGER IF EXISTS journals_immutable_delete")
        execute("DROP TRIGGER IF EXISTS postings_immutable_delete")
        execute("DROP TRIGGER IF EXISTS postings_immutable_update")

      _ ->
        :ok
    end
  end
end
