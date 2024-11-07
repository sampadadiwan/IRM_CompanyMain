class AddTagsToForType < ActiveRecord::Migration[7.1]
  def change
    add_column :form_types, :tag, :string, limit: 50
  end
end
