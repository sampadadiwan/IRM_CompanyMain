class AddPropertiesToSecondarySale < ActiveRecord::Migration[7.0]
  def change
    add_column :secondary_sales, :properties, :text
    add_reference :secondary_sales, :form_type, null: true, foreign_key: true
  end
end
