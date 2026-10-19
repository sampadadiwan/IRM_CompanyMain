# Cache for AI commentary generated for one section of the Account Entries Period
# Report (fund-level when capital_commitment is nil, folio-level when present).
# Not the report itself - AccountEntryReport (a plain service) computes the report
# data fresh on every view; this only caches the narrative built on top of it.
class AccountEntryReportInsight < ApplicationRecord
  STATUSES = %w[pending generating complete error stale].freeze
  SECTION_KEYS = %w[summary_kpis breakdown trend].freeze

  belongs_to :entity
  belongs_to :fund
  attr_readonly :fund_id # never moves to another fund (funds_api_security_policy_plan.md, B)
  belongs_to :capital_commitment, optional: true
  belongs_to :generated_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }, allow_nil: true
  validates :section_key, inclusion: { in: SECTION_KEYS }

  # A section is stale once the underlying account_entries for its scope no longer
  # match what the commentary was generated against (re-run AllocationRun, edits, etc).
  def stale?(current_fingerprint)
    data_fingerprint.present? && data_fingerprint != current_fingerprint
  end

  def self.fingerprint_for(entries_scope)
    count, total = entries_scope.pick(Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(amount_cents), 0)"))
    Digest::SHA256.hexdigest("#{count}:#{total}")
  end
end
