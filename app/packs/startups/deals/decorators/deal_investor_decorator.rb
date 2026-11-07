# The Deal Investors list's rich cells, called by the column keys of DealInvestor::LIST_COLUMNS through
# RansackTableRow (openspec/changes/grid-columns-inline-settings — D21). Same markup the hand-built row had.
class DealInvestorDecorator < ApplicationDecorator
  # The deal's name, linking to the deal for the deal investor's own firm
  def deal_link
    own_firm? ? h.link_to(object.deal_name, object.deal) : object.deal_name
  end

  # The investor's name (a link for the own firm) with its status badge underneath
  def investor_name_with_status
    name = own_firm? ? h.link_to(object.investor_name, object) : object.investor_name
    badge = h.tag.div(h.tag.span(object.status, class: "badge #{h.status_badge(object)}"))
    h.safe_join([name, badge], "\n")
  end

  private

  def own_firm?
    h.belongs_to_entity_id?(h.current_user, object.entity_id)
  end
end
