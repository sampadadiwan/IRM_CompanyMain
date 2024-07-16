class AddForSupportToTask < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :for_support, :boolean, default: false
  end
end
