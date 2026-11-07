# The Portfolio Income list's rich cells, called by the column keys of PortfolioCashflow::LIST_COLUMNS through
# RansackTableRow (openspec/changes/grid-columns-inline-settings — D21). Same markup the hand-built row had.
class PortfolioCashflowDecorator < ApplicationDecorator
  # The fund's name as a link, exactly as the hand-built row rendered it
  def fund_name_link
    h.link_to object.fund.name
  end
end
