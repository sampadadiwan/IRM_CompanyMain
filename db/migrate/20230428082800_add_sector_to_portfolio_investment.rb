class AddSectorToPortfolioInvestment < ActiveRecord::Migration[7.0]
  def change
    remove_column :portfolio_investments, :investment_type
    add_column :portfolio_investments, :sector, :string, limit: 100
    add_column :portfolio_investments, :startup, :boolean, default: true
    add_column :portfolio_investments, :investment_origin, :string, limit: 10, default: "Domestic"    
  end
end
