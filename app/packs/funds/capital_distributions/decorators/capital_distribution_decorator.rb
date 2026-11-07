# The Distributions list's rich cells, called by the column keys of CapitalDistribution::LIST_COLUMNS through
# RansackTableRow (openspec/changes/grid-columns-inline-settings — D21). Same markup the hand-built row had.
class CapitalDistributionDecorator < ApplicationDecorator
  # The distribution's name, linking to it
  def title_link
    h.link_to object.title, object
  end

  # Yes / No badge, as the list showed it
  def approved
    display_boolean(object.approved)
  end
end
