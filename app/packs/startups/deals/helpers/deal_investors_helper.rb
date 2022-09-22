module DealInvestorsHelper
  STATUS_BADGE_MAP = { "Active" => "bg-success", "Pending" => "bg-warning", "Declined" => "bg-danger" }.freeze
  def status_badge(deal_investor)
    STATUS_BADGE_MAP[deal_investor.status]
  end

  def message_badge(message_count)
    message_count.positive? ? "bg-success" : "bg-info"
  end
end
