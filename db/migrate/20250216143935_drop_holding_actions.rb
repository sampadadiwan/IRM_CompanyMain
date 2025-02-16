class DropHoldingActions < ActiveRecord::Migration[7.2]
  def change
    drop_table :holding_actions
    drop_table :holding_audit_trails
    remove_foreign_key :offers, :holdings
    remove_index :offers, :holding_id
  end
end
