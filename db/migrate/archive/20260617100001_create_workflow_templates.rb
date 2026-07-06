# frozen_string_literal: true

class CreateWorkflowTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :workflow_templates do |t|
      t.references :entity, null: false, foreign_key: true
      t.string  :name,                     null: false
      t.text    :description
      t.integer :reminder_interval_days     # nil = no auto-reminders by default
      t.boolean :attach_document_in_email,  null: false, default: false

      t.timestamps
    end
  end
end
