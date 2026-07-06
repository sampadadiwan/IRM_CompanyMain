# frozen_string_literal: true

class CreateWorkflowInstances < ActiveRecord::Migration[7.1]
  def change
    create_table :workflow_instances do |t|
      t.references :folder,            null: false, foreign_key: true
      t.references :workflow_template, null: false, foreign_key: true
      t.references :launched_by,       null: false, foreign_key: { to_table: :users }
      t.json    :template_snapshot,    null: false             # frozen copy of template+steps at launch
      t.integer :current_step_position, null: false, default: 1
      t.integer :status,               null: false, default: 0 # 0=active,1=complete,2=rejected,3=archived

      t.timestamps
    end

    # Only one active instance per folder at a time
    add_index :workflow_instances, [:folder_id, :status],
              name: "index_workflow_instances_on_folder_and_status"
  end
end
