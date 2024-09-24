class AddAdditionalFormTypesToSecondarySale < ActiveRecord::Migration[7.1]
  def change
    add_reference :secondary_sales, :secondary_sale_form_type, null: true, foreign_key: {to_table: :form_types}
    add_reference :secondary_sales, :offer_form_type, null: true, foreign_key: {to_table: :form_types}
    add_reference :secondary_sales, :interest_form_type, null: true, foreign_key: {to_table: :form_types}

    add_column :custom_notifications, :to, :string, limit: 40
  end
end
