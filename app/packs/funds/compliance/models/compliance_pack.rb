# ① A rulebook: CapHive-owned (entity_id NULL, usually locked) or an entity's own fund-agreement pack.
# Its rules live in versions (CompliancePackVersion#definition); this row holds identity, owner,
# lock, the regime time zone and retirement.
# Worked examples H1, H5, E1, E99, X12, X60 — openspec/changes/fund-compliance-monitoring/business-rules.md
class CompliancePack < ApplicationRecord
  belongs_to :entity, optional: true
  has_many :versions, -> { order(:version_no) }, class_name: "CompliancePackVersion", dependent: :destroy, inverse_of: :compliance_pack
  has_many :fund_compliance_packs, dependent: :restrict_with_error

  attr_readonly :entity_id

  validates :name, presence: true, length: { maximum: 120 }
  validates :regime, presence: true, length: { maximum: 30 }
  validates :time_zone, inclusion: { in: ActiveSupport::TimeZone.all.map { |z| z.tzinfo.name } + ActiveSupport::TimeZone::MAPPING.keys }

  # CapHive packs plus the user's own entity packs — never another firm's entity pack (X12)
  scope :visible_to_entity, ->(entity_id) { where(entity_id: nil).or(where(entity_id: entity_id)) }
  scope :caphive, -> { where(entity_id: nil) }

  def caphive?
    entity_id.nil?
  end

  def entity_pack?
    !caphive?
  end

  # Retired from this date on: not attachable, not checked (E1, E99)
  def retired?(on = Time.zone.today)
    retired_on.present? && on >= retired_on
  end

  # Published versions, oldest first
  def published_versions
    versions.select(&:published?)
  end

  # The newest published version — what a fresh attachment starts on
  def latest_published_version
    published_versions.max_by(&:version_no)
  end

  # The version a newly attached fund starts on: the newest effective one in the regime time zone,
  # else the earliest published (a pack published ahead of its first effective date)
  def version_for_new_attachment(fund = nil, on = regime_date)
    published = published_versions.sort_by(&:version_no)
    effective = published.select { |v| v.effective_from && v.effective_from <= on }
    # Skip versions that grandfather this fund (new funds only) — it stays on the older one (E80)
    effective = effective.reject { |v| fund && v.applies_to?(fund) == false }
    effective.last || published.first
  end

  # Draft versions are editable; there is at most one open draft per pack
  def draft_version
    versions.detect(&:draft?)
  end

  # The pack's "today" in its regime time zone (R18)
  def regime_date(at = Time.current)
    at.in_time_zone(time_zone).to_date
  end

  # Attachable means published and not retired (E1, X60)
  def attachable?(on = Time.zone.today)
    latest_published_version.present? && !retired?(on)
  end

  def to_s
    name
  end
end
