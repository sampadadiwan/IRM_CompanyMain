# Document Checks: what the AI reads from each document (doc_checks), each check of one record's
# documents (doc_check_runs) and one outcome per check per run (doc_check_results). Replaces Doc
# Questions — see openspec/changes/document-checks/design.md (Part 4, Data model).
#
# doc_check_conversion_logs records legacy Doc Questions that were reviewed and NOT converted, so the
# retirement migration can tell "skipped on purpose" from "never looked at". It is dropped together
# with doc_questions in the retirement deploy.
#
# Indexes are declared inside create_table so a rollback drops them with the table (MySQL refuses to
# drop an index on its own while a foreign key still needs it).
class CreateDocChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :doc_checks do |t|
      t.references :entity, null: false, foreign_key: true, index: false
      # Registry key: the record type these checks apply to
      t.string :record_type, limit: 40, null: false, default: "InvestorKyc"
      # The document (card) the check reads, from the entity's document lists
      t.string :document_name, limit: 100, null: false
      t.string :action, limit: 12, null: false, default: "fill_in", comment: "fill_in | compare | question"
      # The record field filled in or compared; NULL for a yes-no question
      t.string :field_name, limit: 100
      t.string :look_for, limit: 100, null: false, comment: "What the AI looks for, or the question"
      t.string :tip, limit: 255, comment: "Optional guidance for the AI"
      t.boolean :replace_existing, null: false, default: false, comment: "Fill in: overwrite a value already on the record"
      t.string :expected_answer, limit: 3, null: false, default: "yes"
      t.integer :position, null: false, default: 0
      # No FK: doc_questions is dropped in the retirement deploy, this id must survive it
      t.bigint :legacy_doc_question_id
      t.timestamps
      # A field once per card; questions have a NULL field and are exempt
      t.index %i[entity_id record_type document_name field_name], unique: true, name: "index_doc_checks_on_card_field"
      t.index %i[entity_id record_type document_name look_for], unique: true, name: "index_doc_checks_on_card_look_for"
      t.index :legacy_doc_question_id, unique: true
    end

    create_table :doc_check_runs do |t|
      t.references :entity, null: false, foreign_key: true, index: false
      t.string :record_type, limit: 40, null: false
      t.bigint :record_id, null: false
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :trigger, limit: 10, null: false, default: "manual", comment: "manual | bulk | again | trial"
      t.boolean :trial, null: false, default: false
      # The one run whose results are the record's current results
      t.boolean :current, null: false, default: false
      t.string :status, limit: 15, null: false, default: "queued", comment: "queued | running | done | could_not_run"
      t.integer :documents_total, null: false, default: 0
      t.integer :documents_done, null: false, default: 0
      t.string :current_document, limit: 100
      t.datetime :started_at
      t.datetime :finished_at
      t.string :error_message, limit: 255
      t.json :counts
      t.timestamps
      t.index %i[record_type record_id current], name: "index_doc_check_runs_on_record_current"
      t.index %i[record_type record_id status], name: "index_doc_check_runs_on_record_status"
      t.index %i[entity_id current finished_at], name: "index_doc_check_runs_on_entity_current"
    end

    create_table :doc_check_results do |t|
      t.references :entity, null: false, foreign_key: true, index: false
      t.references :doc_check_run, null: false, foreign_key: { on_delete: :cascade }
      t.references :doc_check, foreign_key: { on_delete: :nullify }
      # Snapshot of the check, so history renders after the check is edited or deleted
      t.string :document_name, limit: 100, null: false
      t.string :look_for, limit: 100, null: false
      t.string :action, limit: 12, null: false
      t.string :field_name, limit: 100
      # The document read and the Shrine file id it had, so a replaced document shows as changed.
      # No FK: documents are soft-deleted.
      t.bigint :document_id
      t.string :document_file_id, limit: 255 # Shrine ids carry the storage path (over 200 chars seen)
      t.string :outcome, limit: 20, null: false, comment: "ok, or the reason it needs attention"
      t.string :note, limit: 255
      t.text :doc_value
      t.text :record_value
      t.text :explanation
      # Use document value / Mark as OK stamp
      t.string :resolution, limit: 20, comment: "marked_ok | used_document_value"
      t.references :resolved_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :resolved_at
      t.string :resolve_reason, limit: 255
      t.timestamps
      t.index %i[entity_id outcome]
    end

    create_table :doc_check_conversion_logs do |t|
      t.references :entity, null: false, foreign_key: true
      t.bigint :doc_question_id, null: false
      t.string :reason, limit: 255, null: false
      t.timestamps
      t.index :doc_question_id, unique: true
    end
  end
end
