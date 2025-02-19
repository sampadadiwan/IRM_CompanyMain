class AddCompliantToPortfolioInvestment < ActiveRecord::Migration[7.1]
  def change
    add_column :portfolio_investments, :compliant, :boolean, default: false
    add_column :capital_commitments, :compliant, :boolean, default: false
    add_column :capital_remittances, :compliant, :boolean, default: false
    add_column :capital_distributions, :compliant, :boolean, default: false
    add_column :investor_kycs, :compliant, :boolean, default: false
  end
end
