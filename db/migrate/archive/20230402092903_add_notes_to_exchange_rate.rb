class AddNotesToExchangeRate < ActiveRecord::Migration[7.0]
  def change
    add_column :exchange_rates, :notes, :text
  end
end
