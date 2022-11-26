class AddLiquidationToFundingRound < ActiveRecord::Migration[7.0]
  def change
    add_column :funding_rounds, :liq_pref_type, :string, limit: 25
    add_column :funding_rounds, :anti_dilution, :string, limit: 50
    add_column :funding_rounds, :price_cents, :decimal, precision: 20, scale: 2, default: 0

    add_column :investments, :liq_pref_type, :string, limit: 25
    add_column :investments, :anti_dilution, :string, limit: 50
  end
end
