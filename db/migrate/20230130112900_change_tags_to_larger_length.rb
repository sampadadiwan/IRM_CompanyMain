class ChangeTagsToLargerLength < ActiveRecord::Migration[7.0]
  def change
    change_column :investors, :tag_list, :string, null: true, limit: 120
    change_column :investment_opportunities, :tag_list, :string, null: true, limit: 120
    change_column :documents, :tag_list, :string, null: true, limit: 120
  end
end
