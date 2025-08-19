class RemoveOldRegulatoryFieldsFromFormCustomFields < ActiveRecord::Migration[8.0]
  def change
    if column_exists?(:form_custom_fields, :regulatory_field)
      remove_column :form_custom_fields, :regulatory_field, :boolean
    end
    if column_exists?(:form_custom_fields, :regulation_type)
      remove_column :form_custom_fields, :regulation_type, :string
    end
  end
end
