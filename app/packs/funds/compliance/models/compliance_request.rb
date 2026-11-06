# ⑦ Maker–checker: an editor requests, a different approver decides (R6, R11).
# kinds: override / disable / detach / explanation / early_adoption / classification
# status: pending → approved / rejected; overrides later become dropped / archived across versions (E92, E93).
# Worked examples H14, H15, H16, E12, E13, X17, X18, X52, X53, X56, H55 — openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md
class ComplianceRequest < ApplicationRecord
  KINDS = %w[override disable detach explanation early_adoption classification].freeze
  STATUSES = %w[pending approved rejected dropped archived].freeze
  # Allow-listed polymorphic targets — never constantized from params (Security item 4)
  TARGET_TYPES = { "FundCompliancePack" => FundCompliancePack, "ComplianceRegisterItem" => ComplianceRegisterItem }.freeze
  MIN_REASON = 10

  belongs_to :entity
  belongs_to :requested_by, class_name: "User"
  belongs_to :decided_by, class_name: "User", optional: true

  # The app's Trackable (soft delete + audits + associated audits), auditing changes and deletions only —
  # the row itself records its creation (who/when columns, created_at) (R177, R178)
  include Trackable.new(on: %i[update destroy])

  attr_readonly :entity_id

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :target_type, inclusion: { in: TARGET_TYPES.keys }
  validate :reason_long_enough, on: :create
  validate :target_in_same_firm, on: :create
  validate :override_allowed, on: :create
  validate :early_adoption_allowed, on: :create

  scope :pending, -> { where(status: "pending") }

  def target
    TARGET_TYPES.fetch(target_type).find_by(id: target_id)
  end

  def payload_hash
    if payload.is_a?(Hash)
      payload
    else
      (payload.present? ? JSON.parse(payload) : {})
    end
  end

  def pending?
    status == "pending"
  end

  # The fund pack this request is about (directly or through a register item)
  def fund_compliance_pack
    t = target
    t.is_a?(ComplianceRegisterItem) ? t.fund_compliance_pack : t
  end

  # Label shown in the register, history and exports (E109, E110)
  def approval_label
    return nil unless status == "approved"

    self_approved? ? "Self-approved — single approver" : "approved by #{decided_by&.full_name}"
  end

  private

  # E13, X17: at least 10 characters
  def reason_long_enough
    return if reason.to_s.strip.length >= MIN_REASON

    errors.add(:base, "Give a reason (at least #{MIN_REASON} characters)")
  end

  # X21, X23: the target must be in the requester's firm
  def target_in_same_firm
    t = TARGET_TYPES[target_type]&.find_by(id: target_id)
    return errors.add(:base, "Target not found") if t.nil?

    errors.add(:base, "Target not found") unless t.entity_id == entity_id
  end

  # X52, X53, X54: overrides on a locked pack only tighten "stricter only" checks
  def override_allowed
    return unless kind == "override"

    fcp = fund_compliance_pack
    check = fcp&.compliance_pack_version&.check(check_key)
    return errors.add(:base, "Unknown check") if check.nil?

    policy = check["override"].presence || (fcp.compliance_pack.locked ? "stricter_only" : "any")
    return errors.add(:base, "This check cannot be overridden") if policy == "none"

    value = payload_hash["limit"]
    return errors.add(:base, "Enter the new limit") if value.blank?

    pack_limit = check.dig("limit", "value")
    return if pack_limit.nil? || policy == "any"

    cmp = ComplianceCheckEvaluator.compare_direction(check)
    if value.to_d == pack_limit.to_d
      errors.add(:base, "Same as the pack's limit")
    elsif !ComplianceCheckEvaluator.stricter?(value.to_d, pack_limit.to_d, cmp)
      errors.add(:base, "Locked pack: overrides can only tighten this limit")
    end
  end

  # X56, X58: only where the newer version allows it, before its effective date, never backwards
  def early_adoption_allowed
    return unless kind == "early_adoption"

    version = CompliancePackVersion.find_by(id: payload_hash["version_id"])
    fcp = fund_compliance_pack
    return errors.add(:base, "Version not found") if version.nil? || fcp.nil? || version.compliance_pack_id != fcp.compliance_pack_id
    return errors.add(:base, "Versions cannot be moved backwards") if fcp.compliance_pack_version && version.version_no <= fcp.compliance_pack_version.version_no

    errors.add(:base, "This version does not allow early adoption") unless version.published? && version.allows_early_adoption
  end
end
