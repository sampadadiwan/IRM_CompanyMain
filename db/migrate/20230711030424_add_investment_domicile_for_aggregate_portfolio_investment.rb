class AddInvestmentDomicileForAggregatePortfolioInvestment < ActiveRecord::Migration[7.0]
  def change
    add_column :aggregate_portfolio_investments, :investment_domicile, :string, limit: 10
    AggregatePortfolioInvestment.all.each do |api|
      api.update(investment_domicile: api.portfolio_investments.first&.investment_domicile)
    end
  end
end
