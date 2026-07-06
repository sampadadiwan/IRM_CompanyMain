# frozen_string_literal: true

class CreateWorkflowActorResponses < ActiveRecord::Migration[7.1]
  def change
    create_table :workflow_actor_responses do |t|
      t.references :workflow_instance, null: false, foreign_key: true
      t.references :actor,             null: false, foreign_key: { to_table: :users }
      t.integer    :step_position,     null: false
      t.string     :state,             null: false
      t.text       :note
      t.integer    :channel,           null: false, default: 0  # 0=ui,1=email_magic_link,2=auto_reminder
      t.datetime   :responded_at,      null: false
      t.boolean    :archived,          null: false, default: false # true when invalidated by restart/revert

      t.timestamps
    end

    add_index :workflow_actor_responses,
              [:workflow_instance_id, :step_position, :actor_id],
              name: "index_wf_actor_responses_on_instance_step_actor"
  end
end
