class AddPortfolioCostTypeToFund < ActiveRecord::Migration[8.0]
  def change
    add_column :funds, :portfolio_cost_type, :string, limit: 10, default: "FIFO", null: false
  end
end
