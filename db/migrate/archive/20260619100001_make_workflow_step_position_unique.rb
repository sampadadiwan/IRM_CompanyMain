# frozen_string_literal: true

# The original migration created a non-unique index on (workflow_template_id, position).
# Replace it with a unique index so duplicate positions within a template are DB-rejected.
class MakeWorkflowStepPositionUnique < ActiveRecord::Migration[7.1]
  def change
    remove_index :workflow_steps, name: "index_workflow_steps_on_template_and_position"
    add_index :workflow_steps, %i[workflow_template_id position],
              unique: true, name: "index_workflow_steps_on_template_and_position"
  end
end
