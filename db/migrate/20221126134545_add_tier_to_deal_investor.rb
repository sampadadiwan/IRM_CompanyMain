class AddTierToDealInvestor < ActiveRecord::Migration[7.0]
  def change
    add_column :deal_investors, :tier, :string, limit: 10
  end
end
