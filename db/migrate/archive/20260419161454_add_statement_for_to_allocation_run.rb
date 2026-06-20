class AddStatementForToAllocationRun < ActiveRecord::Migration[8.1]
  def change
    if column_exists?(:allocation_runs, :statement_for)
      change_column :allocation_runs, :statement_for, :string, limit: 20
    else
      add_column :allocation_runs, :statement_for, :string, limit: 20
    end
  end
end
