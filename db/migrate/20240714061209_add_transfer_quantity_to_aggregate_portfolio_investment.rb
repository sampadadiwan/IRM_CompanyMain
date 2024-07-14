class AddTransferQuantityToAggregatePortfolioInvestment < ActiveRecord::Migration[7.1]
  def change
    add_column :portfolio_investments, :cost_of_remaining_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :portfolio_investments, :unrealized_gain_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :aggregate_portfolio_investments, :unrealized_gain_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :aggregate_portfolio_investments, :transfer_quantity, :decimal, precision: 20, scale: 2, default: 0
    add_column :aggregate_portfolio_investments, :net_bought_amount_cents, :decimal, precision: 20, scale: 2, default: 0
    rename_column :aggregate_portfolio_investments, :cost_cents, :cost_of_remaining_cents


    PortfolioInvestment.all.each do |pi|
      PortfolioInvestmentUpdate.wtf?(portfolio_investment: pi)
    end

    PortfolioInvestment.counter_culture_fix_counts
  end
end
