class RemoveInvestmentOpportunityLinkFromDeal < ActiveRecord::Migration[7.1]
  def change
    if column_exists?(:deals, :investment_opportunity_link)
      remove_column :deals, :investment_opportunity_link
    end
  end
end
