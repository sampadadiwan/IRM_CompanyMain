class ChangeDefaultLockedForAllocationRun < ActiveRecord::Migration[8.0]
  def change
    change_column_default :allocation_runs, :locked, from: nil, to: false
  end
end
