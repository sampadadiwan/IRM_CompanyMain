class AddInvestmentTypeToAggregatePortfolioInvestment < ActiveRecord::Migration[7.0]
  def change
    add_column :aggregate_portfolio_investments, :investment_type, :string, limit: 20
    change_column :portfolio_investments, :investment_type, :string, limit: 20

    PortfolioInvestment.all.each do |pi|
      pi.aggregate_portfolio_investment = nil
      pi.save
    end
  end
end
