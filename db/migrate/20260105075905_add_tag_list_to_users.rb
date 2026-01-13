class AddTagListToUsers < ActiveRecord::Migration[8.0]
  def change
    unless column_exists? :users, :tag_list, :string
      add_column :users, :tag_list, :string
    end
  end
end
