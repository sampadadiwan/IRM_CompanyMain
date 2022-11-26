class RenameDueToCallAmount < ActiveRecord::Migration[7.0]
  def change
    rename_column :capital_calls, :due_amount_cents, :call_amount_cents
    rename_column :capital_remittances, :due_amount_cents, :call_amount_cents
    rename_column :funds, :due_amount_cents, :call_amount_cents
  end
end
