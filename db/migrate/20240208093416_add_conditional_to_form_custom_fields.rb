class AddConditionalToFormCustomFields < ActiveRecord::Migration[7.1]
  def change
    add_column :form_custom_fields, :condition_on, :string
    add_column :form_custom_fields, :condition_criteria, :string, limit: 10, default: 'eq'
    add_column :form_custom_fields, :condition_params, :string
    add_column :form_custom_fields, :condition_state, :string, limit: 5, default: 'show'
  end
end
