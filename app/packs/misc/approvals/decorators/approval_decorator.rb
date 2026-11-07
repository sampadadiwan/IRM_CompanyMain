# The Approvals list's cells, called by the column keys of Approval::LIST_COLUMNS through RansackTableRow
# (openspec/changes/grid-columns-inline-settings — D21). Same markup the hand-built row had.
class ApprovalDecorator < ApplicationDecorator
  STATUS_COLORS = %w[success warning danger primary secondary info].freeze

  def entity_name
    object.entity&.name
  end

  def title_link
    h.link_to object.title, object
  end

  # One badge per response status with its count — for the approval's own firm only, as before (an empty cell
  # for anyone else)
  def responses_status_badges
    return "" unless h.current_user.entity_id == object.entity_id

    status_count = object.approval_responses.group(:status).count
    badges = object.response_status.to_s.split(",").each_with_index.map do |status, idx|
      h.tag.span("#{status} : #{status_count[status] || 0}", class: "badge bg-#{STATUS_COLORS[idx % STATUS_COLORS.length]}")
    end
    h.safe_join(badges, " ")
  end
end
