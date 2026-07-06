# frozen_string_literal: true

class CreateWorkflowSteps < ActiveRecord::Migration[7.1]
  def change
    create_table :workflow_steps do |t|
      t.references :workflow_template, null: false, foreign_key: true
      t.integer :position,             null: false  # 1-based ordering within the template
      t.string  :name,                 null: false
      t.text    :description
      # Comma-separated list of allowable states (e.g. "Approved,Rejected,Needs Info")
      t.string  :states,               null: false, default: "Approved,Rejected,Needs Info"
      t.integer :quorum_rule,          null: false, default: 0   # enum: any_one(0), all(1), majority(2)
      t.integer :on_reject_rule,       null: false, default: 0   # enum: stop(0), previous_step(1), restart(2), go_to_step_n(3)
      # Only used when on_reject_rule = go_to_step_n
      t.integer :on_reject_target_step
      # nil = inherit template-level interval; 0 = disable reminders for this step
      t.integer :reminder_interval_days

      t.timestamps
    end

    add_index :workflow_steps, %i[workflow_template_id position],
              name: "index_workflow_steps_on_template_and_position"
  end
end
