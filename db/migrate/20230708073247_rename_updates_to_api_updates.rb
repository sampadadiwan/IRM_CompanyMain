class RenameUpdatesToApiUpdates < ActiveRecord::Migration[7.0]
  def change
    rename_column :e_signatures, :updates, :api_updates
  end
end
