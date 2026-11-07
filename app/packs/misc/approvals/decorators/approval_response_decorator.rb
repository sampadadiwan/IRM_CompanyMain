# The Approval Responses list's cells, called by the column keys of ApprovalResponse::LIST_COLUMNS through
# RansackTableRow (openspec/changes/grid-columns-inline-settings — D21). Same markup the hand-built row had.
class ApprovalResponseDecorator < ApplicationDecorator
  STATUS_COLORS = %w[bg-success bg-warning bg-secondary bg-info bg-primary bg-light bg-dark].freeze

  def investor_link
    h.link_to object.investor
  end

  def investor_tags
    object.investor.tag_list
  end

  def response_user_name
    object.response_user&.full_name
  end

  # The status as a badge, coloured by its place in the approval's response statuses
  def status_badge
    idx = object.approval.response_status&.split(",")&.index(object.status) || 0
    h.tag.span(object.status, class: "badge #{STATUS_COLORS[idx]}")
  end

  def updated_on
    h.l object.updated_at
  end
end
