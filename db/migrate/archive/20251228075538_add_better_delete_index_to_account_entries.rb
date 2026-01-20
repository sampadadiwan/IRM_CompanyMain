class AddBetterDeleteIndexToAccountEntries < ActiveRecord::Migration[8.0]
  def up

    add_index :valuations,
              [:investment_instrument_id, :deleted_at, :synthetic, :valuation_date],
              name: "idx_latest_valuation"

    add_index :portfolio_attributions,
              [:bought_pi_id, :deleted_at, :sold_pi_id, :quantity],
              name: "idx_pa_bought_deleted_sold_qty"
  end

  def down
    remove_index :portfolio_attributions, name: "idx_pa_bought_deleted_sold_qty"
    remove_index :valuations, name: "idx_latest_valuation"

  end
end
