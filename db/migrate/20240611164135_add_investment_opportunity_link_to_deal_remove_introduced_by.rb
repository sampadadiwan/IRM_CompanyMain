class AddInvestmentOpportunityLinkToDealRemoveIntroducedBy < ActiveRecord::Migration[7.1]
  def change
    if column_exists?(:deal_investors, :introduced_by)
      remove_column :deal_investors, :introduced_by
    end
    unless column_exists?(:deals, :investment_opportunity_link)
      add_column :deals, :investment_opportunity_link, :string
    end
  end
end
