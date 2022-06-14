class AddPositionToFormCustomField < ActiveRecord::Migration[7.0]
  def change
    add_column :form_custom_fields, :position, :integer
  end
end
