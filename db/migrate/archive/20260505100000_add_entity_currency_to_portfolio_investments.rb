class AddEntityCurrencyToPortfolioInvestments < ActiveRecord::Migration[8.0]
  def change
    add_column :portfolio_investments, :entity_currency_amount_cents, :decimal, precision: 20, scale: 2, default: 0.0
    add_column :portfolio_investments, :entity_currency_fmv_cents,    :decimal, precision: 20, scale: 2, default: 0.0
  end
end
