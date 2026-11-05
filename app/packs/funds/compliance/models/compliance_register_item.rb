# ⑥ One breach episode for one check on one fund pack. open_key is "1" while open and NULL when
# closed, so the unique index allows exactly one open item per check (E31, R43).
# status: open / in_progress / pending_approval / explained / closed
# closed_reason: cleared / pack_corrected / record_deleted / check_removed / detached / disabled
# Worked examples H25, H26, E31–E40, X30–X32, E94, H57, E126 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceRegisterItem < ApplicationRecord
  STATUSES = %w[open in_progress pending_approval explained closed].freeze
  CLOSED_REASONS = %w[cleared pack_corrected record_deleted check_removed detached disabled].freeze
  CLOSED_LABELS = {
    "cleared" => "Cleared by data", "pack_corrected" => "Pack corrected", "record_deleted" => "Record deleted",
    "check_removed" => "Check removed", "detached" => "Pack detached", "disabled" => "Check disabled"
  }.freeze

  belongs_to :entity
  belongs_to :fund
  belongs_to :fund_compliance_pack
  belongs_to :first_result, class_name: "ComplianceResult", optional: true
  belongs_to :last_result, class_name: "ComplianceResult", optional: true
  belongs_to :assignee, class_name: "User", optional: true

  audited

  attr_readonly :entity_id

  validates :status, inclusion: { in: STATUSES }
  validates :closed_reason, inclusion: { in: CLOSED_REASONS }, allow_nil: true
  validate :assignee_in_same_firm

  scope :open_items, -> { where(open_key: "1") }
  scope :closed_items, -> { where(open_key: nil) }

  def open?
    open_key == "1"
  end

  def closed?
    !open?
  end

  # Close with a reason (cleared, pack_corrected, …); frees the open_key for a new episode (E37)
  def close!(reason, on: Time.zone.today, result: nil)
    update!(status: "closed", closed_reason: reason, closed_on: on, open_key: nil, last_result: result || last_result)
  end

  # Past the fix-by date (the day after it, not on it — E35, E36, E38)
  def overdue?(on = Time.zone.today)
    open? && fix_by.present? && on > fix_by
  end

  def closed_label
    CLOSED_LABELS[closed_reason]
  end

  def check
    fund_compliance_pack.compliance_pack_version&.check(check_key) ||
      first_result&.compliance_pack_version&.check(check_key)
  end

  def check_name
    check&.dig("name") || check_key.humanize
  end

  # Pending explanation request, if any
  def pending_explanation
    ComplianceRequest.find_by(target_type: "ComplianceRegisterItem", target_id: id, kind: "explanation", status: "pending")
  end

  private

  def assignee_in_same_firm
    return if assignee.nil? || assignee.entity_id == entity_id

    errors.add(:assignee, "must be a user of your firm")
  end
end
