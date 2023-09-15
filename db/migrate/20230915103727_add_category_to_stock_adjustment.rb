class AddCategoryToStockAdjustment < ActiveRecord::Migration[7.0]
  def change
    add_column :stock_adjustments, :category, :string, limit: 10, null: true
    add_column :stock_adjustments, :sub_category, :string, limit: 100, null: true
  end
end
