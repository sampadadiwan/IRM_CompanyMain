module DealActivitiesHelper
  def activity_color(deal_activity)
    if deal_activity.completed == "Yes"
      "btn-outline-outline-success"
    elsif deal_activity.by_date && deal_activity.by_date < Time.zone.today
      "btn-outline-outline-danger"
    elsif deal_activity.by_date && deal_activity.by_date == Time.zone.today && deal_activity.by_date
      "btn-outline-outline-warning"
    else
      "btn-outline-outline-secondary"
    end
  end

  def completed_badge(deal_activity)
    if deal_activity.completed == "Yes"
      "bg-success"
    elsif deal_activity.by_date && deal_activity.by_date < Time.zone.today
      "bg-danger"
    elsif deal_activity.by_date && deal_activity.by_date == Time.zone.today
      "bg-warning"
    else
      "bg-info"
    end
  end
end
