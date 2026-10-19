# NAV of one unit class of an evergreen fund on one date: drafted by FundNavBuilder or uploaded,
# approved by a user with the approver role (FundNavApprove) — who drafted it doesn't matter (review fix 1,
# 10 Oct 2026) — and only then used to price dealing.
# Every line is stored, with its source in `breakdown` and any override in `overrides`.
# Worked examples H3–H6, E7–E12, X5–X9 — openspec/changes/open-ended-funds/design.md#worked-examples
class FundNav < ApplicationRecord
  # Audit trail: every draft, override, approval and reopen, with who and when (Audit Trail screen)
  audited associated_with: :fund
  include ForInvestor

  STATUSES = %w[draft approved].freeze
  SOURCES = %w[computed uploaded].freeze
  # Asset lines add to NAV, liability lines subtract
  ASSET_LINES = %w[investments_fmv cash other_assets].freeze
  # dealing_in_progress: money for orders not yet dealt + dealt-but-unpaid redemptions (E201–E204)
  # class_expenses_payable: expenses charged to this class only (evergreen-share-classes H4, H5)
  LIABILITY_LINES = %w[mgmt_fee_payable perf_fee_payable perf_fee_accrued class_expenses_payable other_liabilities
                       dealing_in_progress].freeze
  LINES = (ASSET_LINES + LIABILITY_LINES).freeze

  belongs_to :entity
  belongs_to :fund
  attr_readonly :fund_id # never moves to another fund (funds_api_security_policy_plan.md, B)
  belongs_to :prepared_by, class_name: "User", optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :import_upload, optional: true
  has_many :dealing_fills, dependent: :restrict_with_error

  validates :unit_type, presence: true, length: { maximum: 40 }
  validates :nav_date, presence: true, uniqueness: { scope: %i[fund_id unit_type] }
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  # X117: a negative NAV (liabilities above assets) is refused — every path (draft, upload, override)
  validate { errors.add(:base, FundNav.negative_message(fund, unit_type, nav_date, nav_cents)) if nav_cents.to_d.negative? }

  # "The NAV for Class A on 31 October 2026 would be negative (₹-80,00,000.00) — …" (X117)
  def self.negative_message(fund, unit_type, nav_date, nav_cents)
    money = ApplicationController.helpers.money_to_currency(Money.new(nav_cents.to_d, fund&.currency || "INR"))
    "The NAV for Class #{unit_type} on #{nav_date && I18n.l(nav_date, format: :day_month_year)} would be negative (#{money}) — " \
      "liabilities exceed assets; check the valuations and ledger balances"
  end

  scope :approved, -> { where(status: "approved") }
  scope :draft, -> { where(status: "draft") }
  scope :for_class, ->(unit_type) { where(unit_type:) }

  # The approved NAV a dealing date or formula prices at: latest on or before the date.
  def self.latest_approved(fund, unit_type, date)
    approved.where(fund_id: fund.id, unit_type:, nav_date: ..date).order(nav_date: :desc).first
  end

  def approved?
    status == "approved"
  end

  def draft?
    status == "draft"
  end

  def uploaded?
    source == "uploaded"
  end

  # Any confirmed dealing date priced at this NAV blocks reopening it.
  # Worked example X9
  def used_by_dealing?
    dealing_fills.exists?
  end

  def used_by_dealing_date
    dealing_fills.joins(:dealing_date).order("dealing_dates.date").first&.dealing_date
  end

  # The approver's late management-fee decisions on this draft (R9.13–R9.15), oldest first:
  # [{"amount_cents", "choice" => "include" | "exclude", "reason", "user_id", "decided_at"}].
  # Kept across recalculation, like overrides. evergreen-late-management-fees H106, H107, E334
  def late_fee_decisions_list
    Array(late_fee_decisions)
  end

  # Late accruals this NAV took a decision on, either way — accounted for, so never late again (R9.15)
  def late_decided_cents
    late_fee_decisions_list.sum { |d| d["amount_cents"].to_d }
  end

  # Of those, the amounts added to this NAV's management fee payable
  def late_included_cents
    late_fee_decisions_list.select { |d| d["choice"] == "include" }.sum { |d| d["amount_cents"].to_d }
  end

  def late_excluded_cents
    late_decided_cents - late_included_cents
  end

  def overrides_hash
    overrides || {}
  end

  def overridden?(line)
    overrides_hash.key?(line.to_s)
  end

  # Recompute NAV and NAV per unit from the stored lines (after an override).
  # With no units outstanding, the class's initial price stands in for NAV per unit (E8).
  def recompute_totals!(initial_price_cents: nil)
    assets = ASSET_LINES.sum { |l| self["#{l}_cents"].to_d }
    liabilities = LIABILITY_LINES.sum { |l| self["#{l}_cents"].to_d }
    self.nav_cents = assets - liabilities
    before_perf = nav_cents + perf_fee_accrued_cents.to_d
    if units_outstanding.to_d.positive?
      self.nav_per_unit_before_perf_cents = (before_perf / units_outstanding).round(4)
      self.nav_per_unit_cents = (nav_cents / units_outstanding).round(4)
    else
      self.nav_per_unit_before_perf_cents = initial_price_cents
      self.nav_per_unit_cents = initial_price_cents
    end
  end

  # Derived on read (never stored as a status): inputs changed since the fingerprint was taken.
  # Worked examples E10, E11
  def stale?
    # Memoized per instance: the NAV page asks several times (banner, Approve, Recalculate) and each
    # fingerprint is a handful of aggregate queries
    return @stale if defined?(@stale)

    @stale = if uploaded? || inputs_fingerprint.blank? || NavStaleness.fingerprint(self) == inputs_fingerprint
               false
             else
               # Drafted before review fix 2: still fresh while the first-version fingerprint matches
               NavStaleness.legacy_fingerprint(self) != inputs_fingerprint
             end
  end

  # A reload (e.g. after a recalculation) must re-check
  def reload(*)
    remove_instance_variable(:@stale) if defined?(@stale)
    super
  end

  def nav_per_unit
    nav_per_unit_cents && (nav_per_unit_cents / 100)
  end

  def to_s
    "NAV #{unit_type} #{I18n.l(nav_date)}"
  end
end
