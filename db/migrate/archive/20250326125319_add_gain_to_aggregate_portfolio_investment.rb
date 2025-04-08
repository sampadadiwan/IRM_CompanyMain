class AddGainToAggregatePortfolioInvestment < ActiveRecord::Migration[8.0]
  def change
    add_column :aggregate_portfolio_investments, :gain_cents, :decimal, precision: 20, scale: 2, default: 0, null: false

    # Fix the data by recomputing the number
    PortfolioInvestment.update_all(unrealized_gain_cents: 0)
    PortfolioInvestment.all.each do |pi|
      pi.compute_all_numbers
      pi.save
    end
    PortfolioInvestment.counter_culture_fix_counts
  end
end
