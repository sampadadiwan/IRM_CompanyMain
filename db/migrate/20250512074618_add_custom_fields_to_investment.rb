class AddCustomFieldsToInvestment < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:investments, :json_fields)
      add_column :investments, :json_fields, :json
    end
    unless column_exists?(:investments, :form_type_id)
      add_reference :investments, :form_type, null: true, foreign_key: true
    end
  end
end
