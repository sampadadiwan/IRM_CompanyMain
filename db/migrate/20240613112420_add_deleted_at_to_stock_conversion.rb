class AddDeletedAtToStockConversion < ActiveRecord::Migration[7.1]
  def change
    add_column :stock_conversions, :deleted_at, :datetime
    add_index :stock_conversions, :deleted_at
  end
end
