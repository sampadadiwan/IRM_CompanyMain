# The Deals index grid's rich cells, called by the column keys of Deal::LIST_COLUMNS / GRID_COLUMNS through
# RansackTableRow. Same markup the deal cards and the old hand-built deals table used.
class DealDecorator < ApplicationDecorator
  # The deal's name, linking to the deal
  def name_link
    h.link_to object.name, h.deal_path(object)
  end

  # Badge colour per Deal::STATUS: an open deal is live (success), a closed one is done (secondary)
  STATUS_BADGE_CLASSES = { "Open" => "bg-success", "Closed" => "bg-secondary" }.freeze

  # The status as a badge, with an "Archived" badge beside it for an archived deal
  def status_badge
    # Status badge first (blank status shows no badge; an unknown status falls back to info)
    badges = []
    badges << h.tag.span(object.status, class: "badge #{STATUS_BADGE_CLASSES.fetch(object.status, 'bg-info')}") if object.status.present?
    # Archived deals are only listed with "View Archived Deals", so flag them in the row
    badges << h.tag.span("Archived", class: "badge bg-danger") if object.archived
    h.safe_join(badges, " ")
  end
end
