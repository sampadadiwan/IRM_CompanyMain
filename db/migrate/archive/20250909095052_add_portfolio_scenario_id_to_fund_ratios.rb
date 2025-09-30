class AddPortfolioScenarioIdToFundRatios < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:fund_ratios, :portfolio_scenario_id)
      add_reference :fund_ratios, :portfolio_scenario, foreign_key: true, null: true
    end
  end
end