class AddInvestmentDomicileToInvestmentInstrument < ActiveRecord::Migration[7.1]
  def change
    add_column :investment_instruments, :investment_domicile, :string, limit: 15
    add_column :investment_instruments, :startup, :boolean, default: false
    add_reference :stock_adjustments, :investment_instrument, null: true, foreign_key: true
  end
end
