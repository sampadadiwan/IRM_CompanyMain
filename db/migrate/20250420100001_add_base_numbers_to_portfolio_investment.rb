class AddBaseNumbersToPortfolioInvestment < ActiveRecord::Migration[8.0]
  def change
    add_column :portfolio_investments, :instrument_currency_fmv_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :aggregate_portfolio_investments, :instrument_currency_fmv_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :portfolio_investments, :instrument_currency_cost_of_remaining_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :aggregate_portfolio_investments, :instrument_currency_cost_of_remaining_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :portfolio_investments, :instrument_currency_unrealized_gain_cents, :decimal, precision: 20, scale: 2, default: 0
    add_column :aggregate_portfolio_investments, :instrument_currency_unrealized_gain_cents, :decimal, precision: 20, scale: 2, default: 0
  end

  def post_deploy
    PortfolioInvestment.all.each do |pi|
      pi.compute_all_numbers
      pi.save
    end;nil
  end
end
