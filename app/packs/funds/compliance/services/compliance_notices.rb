# ⑨ The one place that decides who is told what (design › Notifications). Recipients are named
# roles inside the fund manager's firm only — never investors or advisors (X35):
#   owners    — the compliance owner + active users tagged "Compliance" who can see the fund
#   approvers — eligible approvers (Compliance approver or company admin)
# Worked examples H30, E12, E36, E46, X28, H49, X35 — openspec/changes/fund-compliance-monitoring/business-rules.md
module ComplianceNotices
  TAG = "Compliance".freeze

  module_function

  # H30: the assignee gets email + in-app
  def assignment(item, assignee)
    deliver([assignee], item.entity, "assignment", "#{item.check_name} on #{item.fund.name} assigned to you")
  end

  # E46: approvers (except the requester) are asked to decide
  def approval_requested(request)
    approvers = ComplianceAccess.eligible_approvers(request.entity).reject { |u| u.id == request.requested_by_id }
    deliver(approvers, request.entity, "approval_request", "#{request.kind.humanize} request from #{request.requested_by.full_name} needs approval")
  end

  # E12, E39: the requester hears the decision (in-app)
  def request_decided(request)
    deliver([request.requested_by], request.entity, "decision", "Your #{request.kind.humanize.downcase} request was #{request.status}")
  end

  # E36: past fix-by → owner and approvers, once
  def escalation(item)
    deliver(owners(item.entity, item.fund) + ComplianceAccess.eligible_approvers(item.entity), item.entity, "escalation",
            "Overdue: #{item.check_name} on #{item.fund.name} (fix by #{I18n.l(item.fix_by)})")
  end

  # X28: run failed → owners + CapHive support
  def run_failed(run)
    return if run.nil?

    deliver(owners(run.entity, run.fund), run.entity, "run_failed", "Compliance run failed for #{run.fund.name} on #{I18n.l(run.run_date)}")
    # Support hears about every failed run, not only the owners (R63 → R106)
    ComplianceMailer.with(run_id: run.id).run_failed_support.deliver_later
    Rails.logger.error("[Compliance] run #{run.id} failed for fund #{run.fund_id} — support alerted")
  end

  # H49 / E87: version published, and 7 days before it takes effect
  def version_notice(entity, message)
    deliver(owners(entity), entity, "version", message)
  end

  def digest(entity, user, message, lines, as_of)
    deliver([user], entity, "digest", message, lines:, as_of: as_of.iso8601)
  end

  # Owners: the compliance owner plus active users tagged Compliance (optionally limited to a fund's viewers)
  def owners(entity, fund = nil)
    setup = ComplianceEntitySetup.find_by(entity_id: entity.id)
    users = User.where(entity_id: entity.id, active: true).with_tag(TAG).includes(:roles, :entity).to_a.select { |u| u.tag_list.to_s.split(",").map(&:strip).include?(TAG) }
    users << setup.owner if setup&.owner&.active?
    users = users.uniq.select { |u| ComplianceAccess.viewer?(u) }
    fund ? users.select { |u| ComplianceAccess.fund_visible?(u, fund) } : users
  end

  def deliver(users, entity, kind, message, lines: [], as_of: nil)
    users.compact.uniq.each do |user|
      # Investors and advisors are never compliance recipients (X35)
      next unless ComplianceAccess.employee?(user) && user.entity_id == entity.id

      ComplianceNotifier.with(record: user, entity_id: entity.id, kind:, message:, lines:, as_of:).deliver(user)
    end
  end
end
