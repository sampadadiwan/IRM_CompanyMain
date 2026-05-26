class AddTagListToInvestorAccesses < ActiveRecord::Migration[7.1]
  def change
    add_column :investor_accesses, :tag_list, :string, limit: 120
  end
end
