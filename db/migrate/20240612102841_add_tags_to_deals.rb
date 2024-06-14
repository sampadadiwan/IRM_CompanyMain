class AddTagsToDeals < ActiveRecord::Migration[7.1]
  def change
    add_column :deals, :tags, :string, limit: 50
  end
end
