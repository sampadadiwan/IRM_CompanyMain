class AddTagToReport < ActiveRecord::Migration[7.1]
  def change
    add_column :reports, :tag_list, :string
  end
end
