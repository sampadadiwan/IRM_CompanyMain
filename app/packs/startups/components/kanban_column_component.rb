class KanbanColumnComponent < ViewComponent::Base
  def initialize(deal_activity, deal, current_user, deal_investors)
    super
    @deal_activity = deal_activity
    @deal = deal
    @current_user = current_user
    @deal_investors = deal_investors
  end

  attr_accessor :deal_activity, :deal, :current_user, :deal_investors
end
