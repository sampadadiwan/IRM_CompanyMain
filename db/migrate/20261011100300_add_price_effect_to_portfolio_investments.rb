# Gain split into price effect and currency effect (currency effect = total gain − price effect, so
# the two always add up). Stored for reports. Worked examples H9, E32, E33 — fund-market-data.
class AddPriceEffectToPortfolioInvestments < ActiveRecord::Migration[8.1]
  def change
    change_table :portfolio_investments, bulk: true do |t|
      t.decimal :unrealized_price_effect_cents, precision: 20, scale: 2, null: false, default: 0
      t.decimal :realized_price_effect_cents, precision: 20, scale: 2, null: false, default: 0
    end
    change_table :aggregate_portfolio_investments, bulk: true do |t|
      t.decimal :unrealized_price_effect_cents, precision: 20, scale: 2, null: false, default: 0
      t.decimal :realized_price_effect_cents, precision: 20, scale: 2, null: false, default: 0
    end
  end
end
