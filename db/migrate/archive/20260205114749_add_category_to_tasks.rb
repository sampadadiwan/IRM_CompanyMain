class AddCategoryToTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :category, :string, limit: 40
  end
end
