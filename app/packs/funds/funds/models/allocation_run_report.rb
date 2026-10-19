# The result of running the allocation run checker over one AllocationRun.
#
# The checks themselves are arithmetic and lookups — no AI — so the same run always produces
# the same Pass / Warn / Fail result. See AllocationRunReportBuild for what each check does,
# and docs/modules/allocation/allocation_run_checker_requirements.md for why.
#
# There is exactly one report per run (unique index on allocation_run_id): re-checking a run
# overwrites the previous result in place.
class AllocationRunReport < ApplicationRecord
  # Order matters — the worst finding decides the report's status, so this is used to compare
  # severities as well as to list them.
  SEVERITY_RANK = { "pass" => 0, "skipped" => 1, "warn" => 2, "fail" => 3 }.freeze

  # At most this many affected folios / entry names are stored per finding. A fund with
  # thousands of outliers would otherwise put a multi-megabyte JSON blob in the row, and
  # nobody reads past the first screenful anyway — the count of the rest is kept instead.
  MAX_ROWS_PER_FINDING = 50

  belongs_to :entity
  belongs_to :fund
  attr_readonly :fund_id # never moves to another fund (funds_api_security_policy_plan.md, B)
  belongs_to :user
  belongs_to :allocation_run

  # Deliberately not an ActiveRecord enum: an enum value of "fail" would generate a class-level
  # scope named `fail`, which collides with Kernel#fail. Plain predicates instead.
  STATUSES = %w[Pending Pass Warn Fail Error].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  def pending? = status == "Pending"
  def passed?  = status == "Pass"
  def warned?  = status == "Warn"
  def failed?  = status == "Fail"
  def errored? = status == "Error"

  # True once the job has written a result, whatever that result is.
  def finished? = !pending?

  # Keys of json_fields that belong to the allocation run itself rather than to a check of it.
  # A re-check recomputes findings from the ledger, but these were recorded while the run was
  # happening and cannot be recomputed, so resetting a report for a re-check keeps them.
  # "run_checks" is written by AccountEntryAllocation::RunFormulas (pre/post-run checks).
  RUN_RECORDED_KEYS = %w[run_checks].freeze

  # json_fields cleared for a fresh check, keeping what the run itself recorded.
  # @return [Hash]
  def json_fields_for_recheck
    (json_fields || {}).slice(*RUN_RECORDED_KEYS)
  end

  # The pre/post-run check results the allocation run stored, as plain hashes.
  # @return [Array<Hash>]
  def run_checks
    json_fields&.dig("run_checks") || []
  end

  # The findings, newest write wins, as plain hashes straight out of json_fields.
  # @return [Array<Hash>] one entry per check, in check-number order
  def findings
    json_fields&.dig("findings") || []
  end

  # @param group ["run", "arithmetic"] which section of the requirements doc
  # @return [Array<Hash>] the findings belonging to that section
  def findings_for(group)
    findings.select { |f| f["group"] == group }
  end

  # @param severity [String] one of SEVERITY_RANK's keys
  # @return [Integer] how many checks came out at that severity
  def count_at(severity)
    findings.count { |f| f["severity"] == severity }
  end

  # A report where nothing failed but nothing was actually verified either — a run that only
  # generated statements, or one that has not finished. It comes out as Pass because no check
  # objected, which must not be reported as "every check passed".
  def nothing_checked?
    passed? && count_at("pass").zero?
  end

  # How long the check took, for the report header.
  # @return [String, nil]
  def duration
    json_fields&.dig("duration_ms")&.then { |ms| "#{(ms / 1000.0).round(1)}s" }
  end

  # Bootstrap badge classes for the overall status and for a single finding's severity.
  # Theme colours only — no bespoke hex.
  # Takes either a report status ("Pass") or a finding severity ("pass") — Pending, skipped
  # and anything unrecognised all read as neutral.
  BADGE_CLASSES = {
    "pass" => "bg-success-subtle text-success",
    "warn" => "bg-warning-subtle text-warning",
    "fail" => "bg-danger-subtle text-danger",
    "error" => "bg-danger-subtle text-danger"
  }.freeze

  def self.badge_class(severity)
    BADGE_CLASSES.fetch(severity.to_s.downcase, "bg-secondary-subtle text-secondary")
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[allocation_run_id checked_at fund_id status].sort
  end
end
