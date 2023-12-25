class ChangeFormCustomFieldNameLength < ActiveRecord::Migration[7.1]
  def change
    change_column :form_custom_fields, :name, :string, limit: 100
  end
end
