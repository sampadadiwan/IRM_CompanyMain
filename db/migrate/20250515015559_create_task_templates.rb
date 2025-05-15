class CreateTaskTemplates < ActiveRecord::Migration[8.0]
  def change
    create_table :task_templates do |t|
      t.string :for_class, null: false, limit: 40
      t.string :tag_list, null: false, limit: 100
      t.text :details
      t.integer :due_in_days, default: 1
      t.string :action_link
      t.string :help_link
      t.integer :sequence
      t.references :entity, null: true, foreign_key: true

      t.timestamps
    end

    add_index :task_templates, :for_class
    add_reference :tasks, :task_template, foreign_key: true, null: true

  end
end
