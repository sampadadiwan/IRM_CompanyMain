class AddTagListToInvestor < ActiveRecord::Migration[7.0]
  def change
    add_column :investors, :tag_list, :string, limit: 30
  end
end
