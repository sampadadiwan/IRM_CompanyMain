# frozen_string_literal: true

# Creates customer_support_escalations table for tracking handoffs from CS agent to human support.
class CreateCustomerSupportEscalations < ActiveRecord::Migration[8.1]
  def change
    create_table :customer_support_escalations do |t|
      t.references :agent_chat_session, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true

      t.string :reason, limit: 30, null: false
      t.text :summary, null: true
      t.string :status, limit: 20, default: "open", null: false

      t.references :resolved_by, null: true, foreign_key: { to_table: :users }
      t.datetime :resolved_at, null: true

      t.timestamps
    end

    add_index :customer_support_escalations, :status
    add_index :customer_support_escalations, %i[entity_id status], name: "idx_escalations_entity_status"
  end
end
