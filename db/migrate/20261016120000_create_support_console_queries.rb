# The audit trail of every lookup the Support Console's assistant attempted: who asked, about which
# client, the statement, whether it ran, was blocked or failed, and whether it returned another
# client's rows. Rows outlive the conversation they came from (the FKs to the conversation are
# nullified when it is purged after 90 days).
# openspec/changes/support-console/design.md#data-model-and-schema-changes
class CreateSupportConsoleQueries < ActiveRecord::Migration[8.1]
  def change
    create_table :support_console_queries do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.references :entity, null: false, foreign_key: true, index: false
      t.references :agent_chat_session, null: true, foreign_key: { on_delete: :nullify }
      t.references :agent_chat_message, null: true, foreign_key: { on_delete: :nullify }, index: false
      t.integer :event_seq, null: false
      t.text :sql_text, null: false
      t.string :outcome, limit: 10, null: false
      t.string :reason
      t.boolean :flagged, null: false, default: false
      t.integer :row_count
      t.integer :duration_ms
      t.integer :lag_seconds
      t.string :code_rev, limit: 40, null: false
      t.datetime :created_at, null: false

      t.index %i[entity_id created_at]
      t.index %i[user_id created_at]
      t.index %i[flagged created_at]
      t.index %i[agent_chat_message_id event_seq], unique: true
    end
  end
end
