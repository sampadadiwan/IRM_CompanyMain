class AddCustomMatchingFieldsToSecondarySale < ActiveRecord::Migration[7.0]
  def change
    add_column :secondary_sales, :custom_matching_fields, :text
    add_column :offers, :custom_matching_vals, :text
    add_column :interests, :custom_matching_vals, :text
  end
end
