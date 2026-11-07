# The Secondary Sales list's cells, called by the column keys of SecondarySale::LIST_COLUMNS through RansackTableRow
# (openspec/changes/grid-columns-inline-settings — D21). Same formatting the hand-built row had.
class SecondarySaleDecorator < ApplicationDecorator
  def total_offered_display
    custom_format_number object.total_offered_quantity, h.params
  end

  def entity_name
    object.entity&.name
  end

  def min_price_display
    custom_format_number object.min_price, h.params
  end

  def max_price_display
    custom_format_number object.max_price, h.params
  end

  # Yes while today is within the sale's dates (SecondarySale#active?)
  def active_label
    object.active? ? "Yes" : "No"
  end
end
