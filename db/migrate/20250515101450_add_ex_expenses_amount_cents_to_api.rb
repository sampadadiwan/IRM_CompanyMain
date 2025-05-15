class AddExExpensesAmountCentsToApi < ActiveRecord::Migration[8.0]
  def change
    add_column :aggregate_portfolio_investments, :ex_expenses_amount_cents, :decimal, precision: 20, scale: 2, default: 0
  end
end
