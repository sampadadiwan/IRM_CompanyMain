class AddTagToPortfolioCashflow < ActiveRecord::Migration[7.1]
  def change
    add_column :portfolio_cashflows, :tag, :string, limit: 100, default: ""
    add_column :portfolio_cashflows, :instrument, :string
  end
end
