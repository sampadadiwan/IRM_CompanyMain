class AddPivotCustomFieldsToSecondarySale < ActiveRecord::Migration[7.1]
  def change
    add_column :secondary_sales, :interest_pivot_custom_fields, :text
    add_column :secondary_sales, :offer_pivot_custom_fields, :text
  end
end
