class AddStatusToAllocationRun < ActiveRecord::Migration[7.1]
  def change
    add_column :allocation_runs, :status, :string
  end
end
