class AddPercentInProgressToEntity < ActiveRecord::Migration[7.0]
  def change
    add_column :entities, :percentage_in_progress, :boolean, default: false
  end
end
