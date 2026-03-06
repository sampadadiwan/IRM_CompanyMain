class AddInstrumentToInvestment < ActiveRecord::Migration[8.0]
  def change
    add_column :investments, :instrument_name, :string, limit: 50
    add_column :investments, :instrument_quantity, :decimal, precision: 10, scale: 2
  end
end
