class AddTagListToInvestmentOpportunity < ActiveRecord::Migration[7.0]
  def change
    add_column :investment_opportunities, :tag_list, :string, limit: 60
  end
end
