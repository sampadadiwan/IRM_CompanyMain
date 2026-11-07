# The Funds list's rich cells, called by the column keys of Fund::LIST_COLUMNS / GRID_COLUMNS through
# RansackTableRow (openspec/changes/grid-columns-inline-settings — D21). Same markup the hand-built row had.
class FundDecorator < ApplicationDecorator
  # The fund's name, linking to the fund
  def name_link
    h.link_to object.name, object, aria: { label: "View details for #{object.name}" }
  end

  # The fund's firm (shown to investors, who see funds of several firms)
  def entity_name
    object.entity&.name
  end

  # Closed-ended / Open-ended first, then the fund's own tags, each linking to the funds with that tag
  # (evergreen-fund-on-create). @evergreen_fund_ids is preloaded by FundsController#index.
  def tag_badges
    badges = [h.fund_type_badge(object, h.instance_variable_get(:@evergreen_fund_ids))]
    object.tag_list.to_s.split(",").each do |tag|
      badges << h.tag.span(h.link_to(tag, h.funds_path(tag:)), class: "mb-1 badge rounded-pill font-medium bg-primary text-primary")
    end
    h.safe_join(badges.compact)
  end

  # Distributions are stored negative; the list shows the amount distributed
  def distributed_amount_abs
    object.distribution_amount&.abs
  end
end
