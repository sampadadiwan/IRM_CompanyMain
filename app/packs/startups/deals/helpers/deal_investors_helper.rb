module DealInvestorsHelper
  STATUS_BADGE_MAP = { "Active" => "bg-success", "Pending" => "bg-warning", "Declined" => "bg-danger" }.freeze
  def status_badge(deal_investor)
    STATUS_BADGE_MAP[deal_investor.status]
  end

  def message_badge(message_count)
    message_count.positive? ? "bg-success" : "bg-info"
  end

  def severity_color(deal_investor)
    return "#ADD8E6" if deal_investor.deal_activities.blank? # pale blue

    next_deal_activity = deal_investor.deal_activities.find_by(sequence: (deal_investor.deal_activity.sequence + 1))
    return "#008000" if next_deal_activity.blank? # green

    next_activity_date = (deal_investor.created_at + next_deal_activity.days.days).beginning_of_day
    if next_activity_date > Time.zone.now.beginning_of_day
      "#ADD8E6" # pale blue
    elsif next_activity_date == Time.zone.now.beginning_of_day
      "#FFA500" # orange
    else
      "#FF0000" # red
    end
  end
end
