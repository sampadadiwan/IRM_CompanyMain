class AddFundExpenseToValuation < ActiveRecord::Migration[7.0]
  def change
    add_column :valuations, :portfolio_inv_cost_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :valuations, :management_opex_cost_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :valuations, :portfolio_fmv_valuation_cents, :decimal, precision: 20, scale: 2, default: "0.0"
    add_column :valuations, :collection_last_quarter_cents, :decimal, precision: 20, scale: 2, default: "0.0"
  end
end
