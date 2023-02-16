class AddTotalExpenseToCapitalCommitment < ActiveRecord::Migration[7.0]
  def change
    add_column :capital_commitments, :total_allocated_income_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :capital_commitments, :total_allocated_expense_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :capital_commitments, :total_units_premium_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :fund_units, :premium, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :fund_units, :total_premium_cents, :decimal, precision: 20, scale: 2, default: "0.0"
  end
end
