# The Expressions of Interest list's rich cells, called by the column keys of ExpressionOfInterest::LIST_COLUMNS /
# GRID_COLUMNS through RansackTableRow (openspec/changes/grid-columns-inline-settings — D21). Same output the
# hand-built row had.
class ExpressionOfInterestDecorator < ApplicationDecorator
  # Who created the expression of interest
  def created_by_name
    object.user&.full_name
  end

  # The stakeholder's name as typed on the EOI, else the investor's name
  def stakeholder_name
    object.investor_name.presence || object.investor&.investor_name
  end

  # Yes / No badges, as the list showed them
  def approved_badge
    display_boolean(object.approved)
  end

  def verified_badge
    display_boolean(object.verified)
  end

  def data_room_badge
    display_boolean(object.show_data_room)
  end

  # "12.5 %"
  def allocation_percentage_label
    "#{object.allocation_percentage} %"
  end
end
