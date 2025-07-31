class ChangeQuantityPrecisionInPortfolioInvestments < ActiveRecord::Migration[8.0]
  def up
    change_column :portfolio_investments, :quantity, :decimal, precision: 24, scale: 8, default: 0.0
    change_column :portfolio_investments, :sold_quantity, :decimal, precision: 24, scale: 8, default: 0.0
    change_column :portfolio_investments, :net_quantity, :decimal, precision: 24, scale: 8, default: 0.0    
    change_column :portfolio_attributions, :quantity, :decimal, precision: 24, scale: 8, default: 0.0    
    
    change_column :aggregate_portfolio_investments, :quantity, :decimal, precision: 24, scale: 8, default: 0.0
  end

  def down
    change_column :portfolio_investments, :quantity, :decimal, precision: 20, scale: 2, default: 0.0
    change_column :portfolio_investments, :sold_quantity, :decimal, precision: 20, scale: 2, default: 0.0
    change_column :portfolio_investments, :net_quantity, :decimal, precision: 20, scale: 2, default: 0.0
    change_column :portfolio_attributions, :quantity, :decimal, precision: 20, scale: 2, default: 0.0
    change_column :aggregate_portfolio_investments, :quantity, :decimal, precision: 20, scale: 2, default: 0.0
  end
end
