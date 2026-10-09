# Deploy 2 of Document Checks: Doc Questions is retired. Drops its table, the conversion log the conversion
# wrote, and the dead documents.qna column. investor_kycs.doc_question_answers is kept (shown read-only as
# "Earlier AI answers").
#
# Guarded: it refuses to run while any Doc Question has neither been converted into a check
# (doc_checks.legacy_doc_question_id) nor logged as "not converted" (doc_check_conversion_logs). The
# migration before it, 20261005080000_convert_doc_questions, does both in the same deploy; the guard is the
# safety net. It reads with raw SQL: the models are gone in this release.
# Reversible as structure only: down re-creates the empty tables and column; data comes back from backup.
# See openspec/changes/document-checks/design.md (Retirement) and lld.md. Worked examples R4, R5.
class RetireDocQuestions < ActiveRecord::Migration[8.1]
  # Doc Questions with no check and no "not converted" entry; 0 when the tables are already gone
  def self.unconverted_count(connection = ActiveRecord::Base.connection)
    return 0 unless connection.table_exists?(:doc_questions)

    log_clause = if connection.table_exists?(:doc_check_conversion_logs)
                   "AND q.id NOT IN (SELECT doc_question_id FROM doc_check_conversion_logs)"
                 else
                   ""
                 end
    connection.select_value(<<~SQL.squish).to_i
      SELECT COUNT(*) FROM doc_questions q
      WHERE q.id NOT IN (SELECT legacy_doc_question_id FROM doc_checks WHERE legacy_doc_question_id IS NOT NULL)
      #{log_clause}
    SQL
  end

  def up
    # Step 1: nothing unconverted may be dropped (Worked example R5)
    unconverted = self.class.unconverted_count(connection)
    raise "#{unconverted} Doc Questions are not converted — 20261005080000_convert_doc_questions should have converted or logged them; see its output" if unconverted.positive?

    # Step 2: the legacy tables and the dead column (Worked example R4)
    drop_table :doc_check_conversion_logs, if_exists: true
    drop_table :doc_questions, if_exists: true
    return unless column_exists?(:documents, :qna)

    # INSTANT on MySQL: documents is large, and this column is empty
    if connection.adapter_name.downcase.include?("mysql")
      execute "ALTER TABLE documents DROP COLUMN qna, ALGORITHM=INSTANT"
    else
      remove_column :documents, :qna
    end
  end

  # Structure only (as before deploy 2); the rows come back from backup if ever needed
  def down
    add_column :documents, :qna, :text unless column_exists?(:documents, :qna)

    create_table :doc_questions, if_not_exists: true do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :owner, polymorphic: true, null: false
      t.string :tags, limit: 100
      t.text :question
      t.string :document_name
      t.string :response_hint
      t.string :for_class, limit: 25
      t.string :qtype, limit: 10
      t.integer :import_upload_id
      t.timestamps
    end

    create_table :doc_check_conversion_logs, if_not_exists: true do |t|
      t.references :entity, null: false, foreign_key: true
      t.bigint :doc_question_id, null: false
      t.string :reason, null: false
      t.timestamps
      t.index :doc_question_id, unique: true
    end
  end
end
