# frozen_string_literal: true

class CreateWorkflowStepActors < ActiveRecord::Migration[7.1]
  def change
    create_table :workflow_step_actors do |t|
      t.references :workflow_step, null: false, foreign_key: true
      # Individual entity employee who can respond to this step
      t.references :user,          null: false, foreign_key: true

      t.timestamps
    end

    # Prevent the same user being added twice to a step
    add_index :workflow_step_actors, %i[workflow_step_id user_id],
              unique: true, name: "index_workflow_step_actors_unique"
  end
end
