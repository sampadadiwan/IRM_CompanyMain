# The Allocations list's cells, called by the column keys of Allocation::LIST_COLUMNS through RansackTableRow
# (openspec/changes/grid-columns-inline-settings — D21). Same markup the hand-built row had. The method names are the
# Ransack sort attributes the list sorts by, so the RansackTable heading sort links still sort the right column.
class AllocationDecorator < ApplicationDecorator
  delegate_all

  def offer_full_name
    h.link_to object.offer.full_name, object.offer
  end

  def offer_investor_investor_name
    object.offer.investor.investor_name
  end

  def offer_price
    h.number_with_delimiter object.offer.price
  end

  # With ?debug the quantity still available on the offer, as before
  def offer_quantity
    with_debug(h.number_with_delimiter(object.offer.quantity), object.avail_offer_quantity)
  end

  def interest_buyer_entity_name
    h.link_to object.interest.buyer_entity_name, object.interest
  end

  def interest_investor_investor_name
    object.interest.investor.investor_name
  end

  def interest_price
    h.number_with_delimiter object.interest.price
  end

  # With ?debug the quantity still available on the interest, as before (no delimiter, as the list had it)
  def interest_quantity
    with_debug(object.interest.quantity, object.avail_interest_quantity)
  end

  def quantity
    h.number_with_delimiter object.quantity
  end

  def price
    h.number_with_delimiter object.price
  end

  # Yes / No badge
  def verified
    display_boolean(object.verified)
  end

  private

  # The value, plus a small muted line with the available quantity when the page has ?debug
  def with_debug(value, available)
    return value if h.params[:debug].blank?

    h.safe_join([value.to_s, h.tag.div(available.to_s, class: "small text-muted")])
  end
end
