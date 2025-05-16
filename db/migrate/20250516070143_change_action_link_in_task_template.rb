class ChangeActionLinkInTaskTemplate < ActiveRecord::Migration[8.0]
  def up
    rename_column :task_templates, :sequence, :position
  end

  def down
    rename_column :task_templates, :position, :sequence
  end
end
