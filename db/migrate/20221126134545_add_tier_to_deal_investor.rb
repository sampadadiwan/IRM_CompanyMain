class AddTierToDealInvestor < ActiveRecord::Migration[7.0]
  def change
    add_column :deal_investors, :tier, :string, limit: 10
    Entity.all.each do |e|
      SetupFolders.call(entity: e)
    end
  end
end
