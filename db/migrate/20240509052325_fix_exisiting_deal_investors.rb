class FixExisitingDealInvestors < ActiveRecord::Migration[7.1]
  def change
    deal_investors = DealInvestor.where(deal_activity: nil)
    deal_investors.each_slice(100) do |batch|
      batch.each do |deal_investor|
        deal = deal_investor.deal
        deal_investor.deal_activity = DealActivity.templates(deal).first
        deal_investor.save!
      end
    end
  end
end
