class AddDateToExchangeRate < ActiveRecord::Migration[7.0]
  def change
    add_column :exchange_rates, :as_of, :date
  end
end
