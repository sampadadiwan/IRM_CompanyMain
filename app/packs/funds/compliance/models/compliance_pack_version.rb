# ① One version of a pack's rules. The whole rulebook is one JSON `definition` (classifications,
# inputs, reference lists, measures, checks, duties) validated by ComplianceDefinitionValidator.
# A draft is editable; publishing freezes it. Effective / superseded / retired are derived from dates.
# Worked examples H5, H6, H8, E6, X8, X9, X10, X50, X51, H57 — openspec/changes/fund-compliance-monitoring/business-rules.md
class CompliancePackVersion < ApplicationRecord
  APPLICABILITIES = %w[all new_funds transition].freeze
  STATUSES = %w[draft published].freeze

  belongs_to :compliance_pack
  belongs_to :corrects_version, class_name: "CompliancePackVersion", optional: true
  belongs_to :tested_by, class_name: "User", optional: true
  belongs_to :published_by, class_name: "User", optional: true

  validates :version_no, presence: true, uniqueness: { scope: :compliance_pack_id }
  validates :status, inclusion: { in: STATUSES }
  validates :applicability, inclusion: { in: APPLICABILITIES }
  validate :definition_is_valid

  # Any edit of the rules invalidates an earlier test run (E6, X8)
  before_save :clear_test_on_definition_change

  delegate :entity_id, :caphive?, :locked, :time_zone, to: :compliance_pack

  def draft?
    status == "draft"
  end

  def published?
    status == "published"
  end

  # "v2", or "v2.1" for a correction of v2 (R29)
  def label
    return "v#{version_no}" unless corrects_version

    "v#{corrects_version.version_no}.1"
  end

  def definition_hash
    (definition.is_a?(String) ? JSON.parse(definition) : definition) || {}
  end

  def classifications
    Array(definition_hash["classifications"])
  end

  def checks
    Array(definition_hash["checks"])
  end

  def check(key)
    checks.detect { |c| c["key"] == key }
  end

  def duties
    Array(definition_hash["duties"])
  end

  def measures
    Array(definition_hash["measures"])
  end

  def inputs
    Array(definition_hash["inputs"])
  end

  def period_basis
    definition_hash["period_basis"].presence || "fy_apr"
  end

  def currency
    definition_hash["currency"].presence || "INR"
  end

  # Was this version published after the first run that could have used it? (E114, E115)
  def published_late?
    return false unless published_at && effective_from

    # The 02:00 run on the effective date (regime time zone) is the first that could use it
    first_run_at = ActiveSupport::TimeZone[time_zone].local(effective_from.year, effective_from.month, effective_from.day, 2, 0)
    published_at > first_run_at
  end

  # Fund started before the effective date and the transition has not ended yet (E82, E85)
  def in_transition?(fund, on)
    applicability == "transition" && fund.start_date.present? && effective_from &&
      fund.start_date < effective_from && transition_ends_on && on <= transition_ends_on
  end

  # Does this version apply to the fund under its applicability rule? nil = cannot tell (R4)
  def applies_to?(fund)
    case applicability
    when "new_funds"
      return nil if fund.start_date.nil?

      fund.start_date >= (applicability_date || effective_from)
    when "transition"
      return nil if fund.start_date.nil?

      true
    else
      true
    end
  end

  # Publish with the gates of RL spec: tested since last edit, counsel review (CapHive),
  # applicability, transition end after effective date, effective after the previous version.
  # Worked examples H5, X8, X9, X10, X50, X51, E98
  def publish!(user:, attrs: {})
    assign_attributes(attrs.slice(:effective_from, :applicability, :applicability_date, :transition_ends_on,
                                  :allows_early_adoption, :counsel_reviewer, :counsel_reviewed_on))
    publish_errors.each { |msg| errors.add(:base, msg) }
    return false if errors.any?

    # R19: B applicability date defaults to the effective date
    self.applicability_date ||= effective_from if applicability == "new_funds"
    self.status = "published"
    self.published_by = user
    self.published_at = Time.current
    save
  end

  def publish_errors
    errs = []
    errs << "Run a test first" if tested_at.nil?
    errs << "Record the counsel review" if caphive? && (counsel_reviewer.blank? || counsel_reviewed_on.blank?)
    errs << "Choose who this version applies to" if caphive? && applicability.blank?
    # Entity packs offer no grandfathering or transition (E98)
    errs << "Entity packs apply to all funds" if entity_pack_restricted_applicability?
    errs << "Choose an effective date" if effective_from.blank?
    errs << "Transition must end after the effective date" if applicability == "transition" && (transition_ends_on.blank? || (effective_from && transition_ends_on <= effective_from))
    prev = previous_published
    errs << "Effective date must be after #{prev.label}'s" if prev && effective_from && prev.effective_from && effective_from <= prev.effective_from && !correction_on_same_date?(prev)
    errs
  end

  def previous_published
    compliance_pack.versions.select { |v| v.published? && v.id != id }.max_by(&:version_no)
  end

  def mark_tested!(user)
    update_columns(tested_at: Time.current, tested_by_id: user&.id)
  end

  private

  def entity_pack_restricted_applicability?
    !caphive? && (applicability != "all" || allows_early_adoption)
  end

  # A correction (v2.1) may share the corrected version's effective date (R29)
  def correction_on_same_date?(prev)
    corrects_version_id.present? && corrects_version_id == prev.id && effective_from == prev.effective_from
  end

  def clear_test_on_definition_change
    return unless will_save_change_to_definition? && persisted? && !will_save_change_to_tested_at?

    self.tested_at = nil
    self.tested_by_id = nil
  end

  def definition_is_valid
    return if definition.blank?

    ComplianceDefinitionValidator.call(definition_hash, caphive: compliance_pack&.caphive?).each do |msg|
      errors.add(:base, msg)
    end
  end
end
