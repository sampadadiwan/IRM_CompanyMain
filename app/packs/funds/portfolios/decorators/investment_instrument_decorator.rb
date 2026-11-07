# The Investment Instruments list's rich cells, called by the column keys of InvestmentInstrument::LIST_COLUMNS
# through RansackTableRow (openspec/changes/grid-columns-inline-settings — D21). Same markup the hand-built row had.
class InvestmentInstrumentDecorator < ApplicationDecorator
  # The instrument's name, linking to it
  def name_link
    h.link_to object.name, object
  end

  # The portfolio company, linking to it
  def portfolio_company_link
    h.link_to object.portfolio_company
  end
end
