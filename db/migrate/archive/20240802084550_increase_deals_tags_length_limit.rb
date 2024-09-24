class IncreaseDealsTagsLengthLimit < ActiveRecord::Migration[7.1]
  def change
    change_column :deals, :tags, :string, limit: 100
  end
end
