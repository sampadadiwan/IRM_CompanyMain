class AddPropertiesToSecondarySale < ActiveRecord::Migration[7.0]
  def change
    add_column :secondary_sales, :properties, :text
    add_reference :secondary_sales, :form_type, null: true, foreign_key: true
    add_column :investors, :properties, :text
    add_reference :investors, :form_type, null: true, foreign_key: true
    add_column :offers, :properties, :text
    add_reference :offers, :form_type, null: true, foreign_key: true
    add_column :interests, :properties, :text
    add_reference :interests, :form_type, null: true, foreign_key: true
    add_column :holdings, :properties, :text
    add_reference :holdings, :form_type, null: true, foreign_key: true
    add_column :documents, :properties, :text
    add_reference :documents, :form_type, null: true, foreign_key: true
    add_column :deals, :properties, :text
    add_reference :deals, :form_type, null: true, foreign_key: true
    add_column :option_pools, :properties, :text
    add_reference :option_pools, :form_type, null: true, foreign_key: true
  end
end
