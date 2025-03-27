class AddGainToAggregatePortfolioInvestment < ActiveRecord::Migration[8.0]
  def change
    add_column :aggregate_portfolio_investments, :gain_cents, :decimal, precision: 20, scale: 2, default: 0, null: false

    PortfolioInvestment.counter_culture_fix_counts
  end
end
