class AddValidationRulesToFormCustomFields < ActiveRecord::Migration[7.0]
  def change
    add_column :form_custom_fields, :validation_rules, :json
  end
end
