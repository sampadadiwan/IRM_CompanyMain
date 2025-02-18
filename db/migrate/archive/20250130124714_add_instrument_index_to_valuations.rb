class AddInstrumentIndexToValuations < ActiveRecord::Migration[7.2]
  def change
    
    add_index :valuations, [:owner_id, :owner_type, :investment_instrument_id, :valuation_date, :deleted_at], name: "idx_valuations_full_optimized"

    add_index :portfolio_attributions, [:bought_pi_id, :deleted_at, :sold_pi_id], name: "idx_portfolio_attributions_bought_sold_deleted"

    add_index :portfolio_investments, [:id, :investment_date], name: "idx_portfolio_investments_id_date"

    
    add_index :stock_conversions, [:from_portfolio_investment_id, :conversion_date, :deleted_at], name: "idx_stock_conversions_from_investment_date_deleted"    

    add_index :exchange_rates, [:entity_id, :from, :to, :as_of], order: { as_of: :desc }, name: "idx_exchange_rates_entity_from_to_as_of"

    remove_index :valuations, name: "idx_valuations_full_optimized"

    add_index :valuations, [:owner_id, :owner_type, :deleted_at], name: "idx_valuations_full_optimized"



  end
end
