class AddTrackingCurrencyToEntitySetting < ActiveRecord::Migration[8.0]
  def change
    add_column :entities, :tracking_currency, :string, limit: 4
  end
end
