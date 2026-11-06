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

  # The app's Trackable (soft delete + audits + associated audits), auditing changes and deletions only —
  # the row itself records its creation (who/when columns, created_at) (R177, R178)
  include Trackable.new(on: %i[update destroy])

  attr_readonly :entity_id

  validates :status, inclusion: { in: STATUSES }
  validates :closed_reason, inclusion: { in: CLOSED_REASONS }, allow_nil: true
  validate :assignee_in_same_firm

  scope :open_items, -> { where(open_key: "1") }
  scope :closed_items, -> { where(open_key: nil) }

  # Register grid (RansackTable). Display values come from ComplianceRegisterItemDecorator, which
  # shows the check name, badges and links under the same keys so sorting still uses the columns.
  STANDARD_COLUMNS = {
    "Fund; text-col" => "fund_name; text-col",
    "Pack; text-col" => "pack_name; text-col",
    "Check; text-col" => "check_key; text-col",
    "Opened; date-col" => "opened_on; date-col",
    "Fix by; date-col" => "fix_by; date-col",
    "Assigned to; text-col" => "assignee_first_name; text-col",
    "Status; text-col" => "status; text-col"
  }.freeze

  COLUMN_HELP = {
    "fund_name" => "The fund whose nightly run failed this check",
    "pack_name" => "The rule pack the check belongs to (e.g. SEBI — AIF, or your fund agreement pack)",
    "check_key" => "The check that failed. One item covers the whole breach episode: it stays one row while the check keeps failing",
    "opened_on" => "Date of the first failing run of this episode",
    "fix_by" => "Opened date + the check's time to fix. Past this date the item is overdue and the owner and approvers are told once",
    "assignee_first_name" => "Who is working on it. Assigning emails them",
    "status" => "Open → In progress (assigned) → Pending approval (explanation sent) → Explained, or Closed when a run passes"
  }.freeze

  # Pack name for filtering and sorting (fund pack → pack), as a subquery so no join changes the rows
  ransacker :pack_name do
    Arel.sql("(SELECT compliance_packs.name FROM fund_compliance_packs JOIN compliance_packs " \
             "ON compliance_packs.id = fund_compliance_packs.compliance_pack_id " \
             "WHERE fund_compliance_packs.id = compliance_register_items.fund_compliance_pack_id)")
  end

  # Overdue = open and past fix-by (same rule as #overdue?), so the filter matches the badge
  ransacker :overdue, type: :boolean do
    Arel.sql("(CASE WHEN compliance_register_items.open_key = '1' AND compliance_register_items.fix_by < CURRENT_DATE THEN 1 ELSE 0 END)")
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[check_key closed_on closed_reason escalated_on fix_by opened_on overdue pack_name status].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[assignee fund]
  end

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
