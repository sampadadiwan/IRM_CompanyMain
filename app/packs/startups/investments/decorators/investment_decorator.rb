# The Investments list's rich cells, called by the column keys of Investment::LIST_COLUMNS through RansackTableRow
# (openspec/changes/grid-columns-inline-settings — D21). Same markup the hand-built row had.
class InvestmentDecorator < ApplicationDecorator
  # The portfolio company, linking to it. Named after its Ransack sort key so the column's sort link still sorts.
  def portfolio_company_investor_name
    h.link_to object.portfolio_company
  end

  # "Self" shows as the portfolio company's firm, as the list did (Investment#display_category)
  def category
    object.display_category
  end
end
