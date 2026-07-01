class CreateWorkflowAutoAssignmentRules < ActiveRecord::Migration[7.1]
  def up
    create_table :workflow_auto_assignment_rules, if_not_exists: true do |t|
      t.references :entity,            null: false, foreign_key: true
      t.string     :workflowable_type, null: false   # e.g. "Folder", "InvestorKyc"
      t.references :workflow_template, null: false, foreign_key: true
      t.references :created_by,        null: true,  foreign_key: { to_table: :users }
      t.boolean    :auto_launch,       null: false, default: false
      t.integer    :priority,          null: false, default: 0
      # Conditions are an array of {attribute, operator, value} hashes evaluated AND-wise.
      # Empty array [] means "always match" — acts as a catch-all default.
      # MySQL does not support defaults on TEXT columns — default handled in after_initialize.
      t.text       :conditions,        null: true
      t.timestamps
    end

    add_index :workflow_auto_assignment_rules,
              %i[entity_id workflowable_type priority],
              name: "idx_wf_auto_rules_entity_type_priority",
              if_not_exists: true
  end

  def down
    drop_table :workflow_auto_assignment_rules, if_exists: true
  end
end
