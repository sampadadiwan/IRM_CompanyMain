module DealActivitiesHelper
  def activity_color(deal_activity)
    if deal_activity.Complete?
      "btn-outline-success"
    elsif deal_activity.Incomplete?
      "btn-outline-info"
    elsif deal_activity.by_date && deal_activity.by_date < Time.zone.today
      "btn-outline-danger"
    elsif deal_activity.by_date && deal_activity.by_date == Time.zone.today && deal_activity.by_date
      "btn-outline-warning"
    else
      "btn-outline-secondary"
    end
  end

  def completed_badge(deal_activity)
    if deal_activity.Complete?
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
