class AddAssignedToToTask < ActiveRecord::Migration[7.0]
  def change
    add_column :tasks, :assigned_to_id, :integer
  end
end
