# frozen_string_literal: true

class CreateWorkflowStateChanges < ActiveRecord::Migration[7.1]
  def change
    create_table :workflow_state_changes do |t|
      t.references :workflow_instance, null: false, foreign_key: true
      t.integer    :step_position,     null: false
      t.references :actor,             null: true,  foreign_key: { to_table: :users } # nil for system events
      t.string     :from_state                                # nil at step start
      t.string     :to_state,          null: false
      t.text       :note
      t.integer    :channel,           null: false, default: 0 # 0=ui,1=email_magic_link,2=auto_reminder

      t.timestamps
    end

    add_index :workflow_state_changes, [:workflow_instance_id, :step_position],
              name: "index_wf_state_changes_on_instance_and_step"
  end
end
