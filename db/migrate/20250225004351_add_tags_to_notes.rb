class AddTagsToNotes < ActiveRecord::Migration[7.2]
  def change
    add_column :notes, :tags, :string, limit: 100
  end
end
