class AddFullTextIndexToTagList < ActiveRecord::Migration[7.2]
  def change
    add_index :investors, :tag_list, type: :fulltext
  end
end
