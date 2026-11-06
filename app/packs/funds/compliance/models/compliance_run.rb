# ⑤ One run of one fund (nightly or Run now). Status drives run health / staleness (E28, X28, R22).
# Worked examples H19, E18, X28, E132 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceRun < ApplicationRecord
  TRIGGERS = %w[nightly run_now].freeze
  STATUSES = %w[running succeeded failed].freeze
  STALE_AFTER = 26.hours

  belongs_to :entity
  belongs_to :fund
  has_many :compliance_results, dependent: :restrict_with_error

  attr_readonly :entity_id

  validates :trigger, inclusion: { in: TRIGGERS }
  validates :status, inclusion: { in: STATUSES }

  scope :succeeded, -> { where(status: "succeeded") }

  # Latest successful run for a fund — "Last successful run" banner
  def self.last_success_for(fund)
    succeeded.where(fund_id: fund.id).order(:finished_at, :id).last
  end

  # Results older than 26 hours are "may be out of date"; 25 h is current (E28, R15)
  def self.stale?(fund, now: Time.current)
    last = last_success_for(fund)
    last.nil? || last.finished_at.nil? || (now - last.finished_at) > STALE_AFTER
  end
end
