class AddReadOnlyToFormCustomField < ActiveRecord::Migration[7.0]
  def change
    add_column :form_custom_fields, :read_only, :boolean, default: false
  end
end
