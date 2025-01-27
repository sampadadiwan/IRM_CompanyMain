class ChangeAllocationRunStatus < ActiveRecord::Migration[7.2]
  def change
    change_column :allocation_runs, :status, :text
  end
end
