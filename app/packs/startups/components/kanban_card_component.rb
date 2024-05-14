class KanbanCardComponent < ViewComponent::Base
  def initialize(deal_investor, deal, deal_activity, current_user, deal_investor_id: nil)
    super
    @deal_investor = deal_investor.presence || DealInvestor.find(deal_investor_id)
    @deal = deal
    @deal_activity = deal_activity
    @title = deal_investor.investor_name
    @current_user = current_user
  end

  attr_accessor :deal_investor, :deal, :deal_activity, :title, :current_user
end
