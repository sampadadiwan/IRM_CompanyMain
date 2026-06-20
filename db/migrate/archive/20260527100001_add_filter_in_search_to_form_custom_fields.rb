class AddFilterInSearchToFormCustomFields < ActiveRecord::Migration[8.0]
  def change
    add_column :form_custom_fields, :filter_in_search, :boolean, default: false, null: false
  end
end
