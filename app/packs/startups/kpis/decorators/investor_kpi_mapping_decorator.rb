# The Investor KPI Mappings list's rich cells, called by the column keys of InvestorKpiMapping::LIST_COLUMNS /
# GRID_COLUMNS through RansackTableRow (openspec/changes/grid-columns-inline-settings — D21). Same output the
# hand-built row had.
class InvestorKpiMappingDecorator < ApplicationDecorator
  # "Last value" for "last_value"
  def autofill_label
    object.autofill&.humanize
  end

  # Yes / No badges, as the list showed them
  def common_size_badge
    display_boolean(object.base_for_common_size)
  end

  def show_in_report_badge
    display_boolean(object.show_in_report)
  end
end
