class AddCategoryToValuation < ActiveRecord::Migration[7.0]
  def change
    remove_column :valuations, :instrument_type
    add_column :valuations, :category, :string, limit: 10, null: true
    add_column :valuations, :sub_category, :string, limit: 100, null: true
  end
end
