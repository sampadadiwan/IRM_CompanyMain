# Fund compliance monitoring — Phase 3: AI document reading and the facts a person confirms.
# Design: openspec/changes/fund-compliance-monitoring/design.md › document_readings, document_facts
# New tables only; no existing table is altered.
class CreateDocumentReadingsAndFacts < ActiveRecord::Migration[8.1]
  def change
    # One read of one document version for one pack input (read once per version — E68)
    create_table :document_readings do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: true, index: false
      t.string :input_key, limit: 80, null: false
      # Stored file id + size: a replaced file gets a new checksum, so it is read again (E68)
      t.string :file_checksum, limit: 64, null: false
      # Hash of the declared fact keys: a pack version adding a fact queues a re-read (R17, E130)
      t.string :facts_signature, limit: 64, null: false
      # queued / capped / read / failed / manual (manual = facts entered by hand, nothing sent — H43)
      t.string :status, limit: 10, null: false, default: "queued"
      # Record what was sent (design › Record what was sent)
      t.string :llm_model, limit: 80
      t.bigint :byte_size
      t.datetime :sent_at
      t.string :failure_reason, limit: 120
      # Kind-4 duties: AI notes for a person (H44)
      t.text :notes
      t.timestamps
      t.index %i[document_id input_key file_checksum facts_signature], unique: true, name: "idx_doc_readings_unique"
      t.index %i[entity_id sent_at], name: "idx_doc_readings_cap"
    end

    # One fact read from (or entered for) a document; counts only once confirmed (E66)
    create_table :document_facts do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :document_reading, null: false, foreign_key: true, index: false
      t.string :fact_key, limit: 80, null: false
      t.string :value_type, limit: 10, null: false
      t.json :value
      t.text :quote
      t.integer :page
      t.string :source, limit: 10, null: false, default: "ai"
      t.string :status, limit: 10, null: false, default: "ai_read"
      t.references :confirmed_by, foreign_key: { to_table: :users }
      t.datetime :confirmed_at
      t.timestamps
      t.index %i[document_reading_id fact_key], unique: true, name: "idx_doc_facts_unique"
    end
  end
end
