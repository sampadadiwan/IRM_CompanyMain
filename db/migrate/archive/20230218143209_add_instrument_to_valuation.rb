class AddInstrumentToValuation < ActiveRecord::Migration[7.0]
  def change
    add_column :valuations, :instrument_type, :string, limit: 15
    remove_column :valuations, :portfolio_inv_cost_cents
    remove_column :valuations, :management_opex_cost_cents
    remove_column :valuations, :portfolio_fmv_valuation_cents
    remove_column :valuations, :collection_last_quarter_cents
    change_column :portfolio_investments, :investment_type, :string, limit: 15

  end
end
