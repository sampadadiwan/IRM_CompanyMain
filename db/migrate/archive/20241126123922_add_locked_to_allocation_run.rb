class AddLockedToAllocationRun < ActiveRecord::Migration[7.2]
  def change
    unless column_exists?(:allocation_runs, :locked)
      add_column :allocation_runs, :locked, :boolean
    end
  end
end
