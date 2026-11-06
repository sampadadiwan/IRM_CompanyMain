# ② A pack attached to a fund: the fund's classification under that pack and the version the fund
# is currently on (moved forward by ComplianceVersionMover on effective dates; grandfathered funds stay).
# Worked examples H11, H12, E9, E11, E16, X14, X23, H16 — openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md
class FundCompliancePack < ApplicationRecord
  STATUSES = %w[active detached].freeze

  belongs_to :entity
  belongs_to :fund
  belongs_to :compliance_pack
  belongs_to :compliance_pack_version, optional: true
  has_many :compliance_results, dependent: :restrict_with_error
  has_many :compliance_register_items, dependent: :restrict_with_error
  has_many :compliance_duties, dependent: :restrict_with_error

  attr_readonly :entity_id

  validates :status, inclusion: { in: STATUSES }
  # X14, E16: one pack once per fund
  validates :compliance_pack_id, uniqueness: { scope: :fund_id, message: ->(rec, _) { "#{rec.compliance_pack&.name} is already attached to this fund" } }
  validate :fund_in_same_firm
  validate :pack_visible_and_attachable, on: :create
  validate :classification_in_pack

  before_validation :default_version_and_date, on: :create

  scope :active, -> { where(status: "active") }

  delegate :name, to: :compliance_pack, prefix: :pack

  def active?
    status == "active"
  end

  # Transient, per fund run: the attachment's open register items by check (ComplianceRunOperation, R176)
  attr_accessor :run_open_items

  # A fund run reads the override / disable requests of every attachment in one query (R176)
  def self.preload_requests(fund_packs)
    by_fp = ComplianceRequest.where(target_type: "FundCompliancePack", target_id: fund_packs.map(&:id),
                                    kind: %w[override disable], status: %w[approved pending]).group_by(&:target_id)
    fund_packs.each { |fp| fp.instance_variable_set(:@preloaded_requests, by_fp[fp.id] || []) }
  end

  def clear_preloaded_requests
    @preloaded_requests = nil
  end

  # Approved, not archived/dropped overrides for this attachment, keyed by check
  def active_overrides
    requests_of("override", "approved").index_by(&:check_key)
  end

  # Checks switched off for this fund (approved disable requests)
  def disabled_check_keys
    requests_of("disable", "approved").map(&:check_key)
  end

  # Overrides waiting for an approver (the old limit keeps applying)
  def pending_override_keys
    requests_of("override", "pending").map(&:check_key)
  end

  # E15/H18-style labels: "SEBI — AIF · Category II"
  def to_s
    [pack_name, classification].compact_blank.join(" · ")
  end

  private

  def default_version_and_date
    self.entity_id ||= fund&.entity_id
    self.compliance_pack_version ||= compliance_pack&.version_for_new_attachment(fund)
    self.attached_on ||= Time.zone.today
  end

  # X23: never attach to another firm's fund
  def fund_in_same_firm
    return if fund.nil? || fund.entity_id == entity_id

    errors.add(:fund, "is not in your firm")
  end

  # X12, X60: only CapHive packs or the entity's own; never a retired or unpublished pack
  def pack_visible_and_attachable
    return if compliance_pack.nil?
    return errors.add(:base, "Pack not found") unless compliance_pack.entity_id.nil? || compliance_pack.entity_id == entity_id

    errors.add(:base, "#{compliance_pack.name} is retired") if compliance_pack.retired?
    errors.add(:base, "#{compliance_pack.name} has no published version") if compliance_pack.latest_published_version.nil?
  end

  # A classification, when given, must be one the pack (current version) defines
  def classification_in_pack
    return if classification.blank? || compliance_pack_version.nil?
    return if compliance_pack_version.classifications.include?(classification)

    errors.add(:classification, "\"#{classification}\" is not a classification of #{pack_name}")
  end

  def requests_of(kind, status)
    if @preloaded_requests
      @preloaded_requests.select { |r| r.kind == kind && r.status == status }
    else
      ComplianceRequest.where(target_type: "FundCompliancePack", target_id: id, kind:, status:).to_a
    end
  end
end
