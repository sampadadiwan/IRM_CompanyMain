class AddLabelToFormCustomField < ActiveRecord::Migration[7.1]
  def change
    add_column :form_custom_fields, :label, :string
  end
end
