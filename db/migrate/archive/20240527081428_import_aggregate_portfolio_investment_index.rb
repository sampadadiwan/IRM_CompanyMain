class ImportAggregatePortfolioInvestmentIndex < ActiveRecord::Migration[7.1]
  def change
    AggregatePortfolioInvestmentIndex.import
  end
end
