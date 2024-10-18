module InterestsHelper
  def interest_by_quantity(secondary_sale)
    interests = secondary_sale.interests
    if interests.count < 10
      grouped = interests.map { |k| [k.buyer_entity_name, k.quantity] }
    else
      grouped = interests.order(quantity: :desc).limit(10).map { |k| [k.buyer_entity_name, k.quantity] }
      # This is to get the sum of the other
      row = Interest.connection.select_one("select sum(quantity) from (#{interests.order(quantity: :desc).offset(10).to_sql}) q")
      others_quantity = row["sum(quantity)"]
      grouped << ["Others", others_quantity]
    end

    pie_chart_with_options grouped
  end

  def interest_by_shortlisted(secondary_sale)
    short_listed_quantity = secondary_sale.interests.short_listed.sum(:quantity)
    pending_quantity = secondary_sale.interests.pending.sum(:quantity)
    rejected_quantity = secondary_sale.interests.rejected.sum(:quantity)
    grouped = [
      ["Shortlisted", short_listed_quantity],
      ["Pending", pending_quantity],
      ["Rejected", rejected_quantity]
    ]

    pie_chart_with_options grouped
  end

  def interest_by_allocation(secondary_sale)
    allocated_interests = secondary_sale.interests.where(allocation_quantity: 0..).count
    unallocated_interests = secondary_sale.interests.where(allocation_quantity: 0).count
    grouped = [
      ["Allocated", allocated_interests],
      ["Un Allocated", unallocated_interests]
    ]

    pie_chart_with_options grouped
  end

  def short_listed_css(interest)
    case interest.short_listed_status
    when Interest::STATUS_SHORT_LISTED
      "bg-success"
    when Interest::STATUS_PENDING
      "bg-warning"
    when Interest::STATUS_REJECTED
      "bg-danger"
    when Interest::STATUS_WITHDRAWN
      "bg-muted bg-opacity-50"
    end
  end

  def short_listed_status(interest)
    "<span class='badge #{short_listed_css(interest)}'>
      #{interest.short_listed_status.humanize}
    </span>"
  end
end
