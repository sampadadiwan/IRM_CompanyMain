class AddInternalToFormCustomField < ActiveRecord::Migration[7.1]
  def change
    add_column :form_custom_fields, :internal, :boolean, default: false
  end
end
