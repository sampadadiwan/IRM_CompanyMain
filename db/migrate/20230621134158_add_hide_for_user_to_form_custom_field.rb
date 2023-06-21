class AddHideForUserToFormCustomField < ActiveRecord::Migration[7.0]
  def change
    add_column :form_custom_fields, :hide_user_ids, :string, limit: 50
  end
end
