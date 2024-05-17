class AddRunAllocationsToAllocationRun < ActiveRecord::Migration[7.1]
  def change
    add_column :allocation_runs, :run_allocations, :boolean, default: true
  end
end
