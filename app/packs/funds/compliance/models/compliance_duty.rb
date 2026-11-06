# ⑥ One occurrence of a manual duty (scheduled per period, on demand, or per event subject).
# Scheduled / Due / Overdue / Done are derived from dates (no status column).
# Worked examples H27, H28, E41–E44, X33, X37, E117–E122 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceDuty < ApplicationRecord
  include WithFolder

  REMINDER_DAYS = 7

  belongs_to :entity
  belongs_to :fund_compliance_pack
  belongs_to :owner, class_name: "User", optional: true
  belongs_to :done_by, class_name: "User", optional: true
  has_one :fund, through: :fund_compliance_pack

  audited

  attr_readonly :entity_id

  validates :duty_key, presence: true

  scope :not_done, -> { where(done_on: nil) }

  # Duties grid (RansackTable); display values come from ComplianceDutyDecorator
  STANDARD_COLUMNS = {
    "Fund; text-col" => "fund_name; text-col",
    "Duty; text-col" => "duty_key; text-col",
    "Period; text-col" => "period_key; text-col",
    "Due; date-col" => "due_on; date-col",
    "Owner; text-col" => "owner_first_name; text-col",
    "State; text-col" => "done_on; text-col"
  }.freeze

  COLUMN_HELP = {
    "duty_key" => "Something a person must do and prove, that data cannot show — e.g. a filed report",
    "period_key" => "The period this occurrence is for (FY27-Q3 = Oct–Dec 2026), or the investor/document it was created for",
    "due_on" => "When it must be done. The digest reminds the owner 7 days before",
    "owner_first_name" => "The duty's owner, else the firm's compliance owner",
    "done_on" => "Scheduled → Due (7 days before) → Overdue (after the due date) → Done. Done late shows how many days late"
  }.freeze

  # Overdue = not done and past the due date (same rule as #state)
  ransacker :overdue, type: :boolean do
    Arel.sql("(CASE WHEN compliance_duties.done_on IS NULL AND compliance_duties.due_on < CURRENT_DATE THEN 1 ELSE 0 END)")
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[done_on due_on duty_key overdue period_key].sort
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[fund owner]
  end

  def definition
    fund_compliance_pack.compliance_pack_version&.duties&.detect { |d| d["key"] == duty_key } || {}
  end

  def name
    definition["name"].presence || duty_key.humanize
  end

  def evidence_required?
    definition["evidence"] == true
  end

  def done?
    done_on.present?
  end

  # Derived state (E41, E42, E43)
  def state(on = Time.zone.today)
    return "done" if done?
    return "due" if due_on.nil?
    return "overdue" if on > due_on
    return "due" if on >= due_on - REMINDER_DAYS

    "scheduled"
  end

  # "late (3 days)" when done after the due date (E43)
  def late_days
    return 0 unless done? && due_on

    [(done_on - due_on).to_i, 0].max
  end

  def subject
    return nil if subject_type.blank? || subject_id.zero?

    { "Investor" => Investor, "CapitalCommitment" => CapitalCommitment, "Document" => Document }[subject_type]&.find_by(id: subject_id)
  end

  def folder_path
    "#{fund_compliance_pack.fund.folder_path}/Compliance/#{duty_key}"
  end

  def document_list
    ["Evidence"]
  end
end
