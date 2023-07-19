class ChangeInvestmentTypeInApi < ActiveRecord::Migration[7.0]
  def change
    change_column :aggregate_portfolio_investments, :investment_type, :string, length: 120
  end
end
