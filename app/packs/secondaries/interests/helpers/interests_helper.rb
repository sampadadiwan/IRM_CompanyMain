module InterestsHelper
  def interest_by_quantity(secondary_sale)
    interests = secondary_sale.interests
    grouped = interests
              .map { |k| [k.buyer_entity_name, k.quantity] }

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
    allocated_interests = secondary_sale.interests.where(allocation_quantity: 0..).sum(:quantity)
    unallocated_interests = secondary_sale.interests.where(allocation_quantity: 0).sum(:quantity)
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
    end
  end
end
