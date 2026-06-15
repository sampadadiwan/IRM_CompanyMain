# frozen_string_literal: true

# Creates agent_chat_message_feedbacks table for user ratings, LLM judge scores, and review queue.
class CreateAgentChatMessageFeedbacks < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_chat_message_feedbacks do |t|
      t.references :agent_chat_message, null: false, foreign_key: true, index: { unique: true }
      t.references :user, null: true, foreign_key: true
      t.references :entity, null: false, foreign_key: true

      # User feedback
      t.string :channel, limit: 20, default: "web", null: false
      t.string :rating, limit: 10, null: true
      t.text :notes, null: true

      # LLM judge scores
      t.integer :judge_completeness, null: true
      t.integer :judge_grounding, null: true
      t.integer :judge_actionability, null: true
      t.integer :judge_total, null: true
      t.json :judge_issues, null: true

      # Review queue
      t.string :status, limit: 25, default: "open", null: false
      t.json :guide_files_searched, null: true
      t.text :resolution_notes, null: true
      t.references :reviewed_by, null: true, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :agent_chat_message_feedbacks, :status
    add_index :agent_chat_message_feedbacks, :rating
    add_index :agent_chat_message_feedbacks, %i[entity_id status], name: "idx_feedbacks_entity_status"
  end
end
