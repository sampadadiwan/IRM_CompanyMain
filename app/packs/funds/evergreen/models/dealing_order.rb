# A subscription or redemption order on an evergreen fund, from the portal wizard, an admin or an
# upload. Queue position and "ready to deal" are derived, never stored.
# Worked examples H7–H15, E13–E22, X10–X16 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingOrder < ApplicationRecord
  # Audit trail of order changes (e.g. a subscription reduced to the amount received)
  audited associated_with: :fund
  include ForInvestor
  # Optional per-order journey (US-14): launched by the entity's catch-all rule, kept off by
  # skip_journey? for funds (or order kinds) with order journeys off
  include Workflowable

  has_journey

  KINDS = %w[subscription redemption].freeze
  STATUSES = %w[pending partially_filled dealt cancelled rejected].freeze
  OPEN_STATUSES = %w[pending partially_filled].freeze
  SOURCES = %w[portal admin upload].freeze

  class NoNav < StandardError; end

  belongs_to :entity
  belongs_to :fund
  belongs_to :investor
  belongs_to :capital_commitment, optional: true
  # The investing entity the order is for; a folio the order opens takes it (evergreen-folio-soa ①)
  belongs_to :investor_kyc, optional: true
  belongs_to :dealing_date
  belongs_to :capital_remittance, optional: true
  belongs_to :entered_by, class_name: "User", optional: true
  belongs_to :amount_reduced_by, class_name: "User", optional: true

  # Per-lot fee rates found at acceptance ("100 at 3%, 100 at 2%"), shown with the fee note (E86)
  attr_accessor :fee_breakdown

  belongs_to :import_upload, optional: true
  belongs_to :accepted_by, class_name: "User", optional: true
  belongs_to :signatory_verified_by, class_name: "User", optional: true
  belongs_to :cancelled_by, class_name: "User", optional: true
  has_many :dealing_fills, dependent: :restrict_with_error

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validates :unit_type, presence: true, length: { maximum: 40 }
  validates :received_at, presence: true
  validates :rejected_reason, length: { maximum: 255 }

  scope :subscriptions, -> { where(kind: "subscription") }
  scope :redemptions, -> { where(kind: "redemption") }
  scope :open_orders, -> { where(status: OPEN_STATUSES) }
  scope :in_queue_order, -> { order(:received_at, :id) }

  def subscription?
    kind == "subscription"
  end

  def redemption?
    kind == "redemption"
  end

  def pending?
    status == "pending"
  end

  def open?
    OPEN_STATUSES.include?(status)
  end

  def cancellable?
    pending? && dealing_date.open?
  end

  def setting
    fund.evergreen_fund_setting
  end

  # Rank among the open redemptions this order actually competes with for the gate, by received time,
  # then id. Worked examples H10, E22, H26.
  #
  # Review fix 7 (10 Oct 2026): the rank used to count every open redemption of the fund — every
  # dealing date and every class — so an order could read "#14" on a date with three requests. The
  # gate fills one dealing date at a time (DealingPricer / GateAllocator), and with a class-level gate
  # each class has its own pool, so the queue is the same dealing date (and the same class when the
  # gate is per class).
  def queue_position
    return nil unless redemption? && open? && dealing_date

    self.class.redemption_queue(fund, dealing_date.date, unit_type)
        .where("dealing_orders.received_at < :t OR (dealing_orders.received_at = :t AND dealing_orders.id < :id)", t: received_at, id: id || 0)
        .count + 1
  end

  # The open redemptions sharing one gate on a dealing date: the date's, and the class's too when the
  # fund's gate is per class (review fix 7). Also used by the order preview's "You would be #N".
  def self.redemption_queue(fund, date, unit_type)
    queue = where(fund_id: fund.id, kind: "redemption", status: OPEN_STATUSES).joins(:dealing_date).where(dealing_dates: { date: })
    fund.evergreen_fund_setting&.gate_level == "class" ? queue.where(unit_type:) : queue
  end

  # Derived: priced on a dealing date only when valid, journey done and (pre-funded) fully paid.
  # Worked examples E19, E21, E24, E25
  def ready_to_deal?
    return false unless pending? || status == "partially_filled"
    return false unless journey_ready?
    return true if redemption? || !setting.pre_funded?

    fully_paid?
  end

  # With an order journey the journey's pre-deal steps must be cleared; without one, always ready
  def journey_ready?
    return true if skip_journey? || workflow_template.nil?

    OrderJourneyStatus.ready_to_deal?(self)
  end

  # Pre-funded subscriptions: the subscription payment is verified for the full amount.
  # Reduced to the amount received ("Accept received amount")
  def amount_reduced?
    original_amount_cents.present? && original_amount_cents.to_d != amount_cents.to_d
  end

  # Money received but short of the amount asked: the GP may accept it as the subscription
  def part_paid?
    rem = capital_remittance
    subscription? && rem.present? && rem.collected_amount_cents.to_d.positive? &&
      rem.collected_amount_cents.to_d < rem.call_amount_cents.to_d - 10
  end

  def fully_paid?
    rem = capital_remittance
    rem.present? && rem.verified && rem.collected_amount_cents.to_d >= amount_cents.to_d - 10
  end

  # Units held in the folio's class as of a time (all units / free-unit checks).
  def units_held(as_of: Time.zone.today)
    return 0.to_d unless capital_commitment

    FundUnit.where(capital_commitment_id: capital_commitment_id, unit_type:, issue_date: ..as_of).sum(:quantity).to_d
  end

  # Units already dealt for redemption but not yet paid (their FundUnits are created when paid), so
  # they still count in units_held but can't be redeemed again (review finding: double redemption)
  def unsettled_redemption_units(excluding_date_id: nil)
    return 0.to_d unless capital_commitment

    fills = DealingFill.joins(:dealing_order).where(kind: "redemption", fund_unit_id: nil, unit_type:)
                       .where(dealing_orders: { capital_commitment_id: })
    fills = fills.where.not(dealing_date_id: excluding_date_id) if excluding_date_id
    fills.sum(:units).to_d
  end

  # Units the folio can still redeem: held minus dealt-but-unpaid redemptions
  def free_units(as_of: Time.zone.today, excluding_date_id: nil)
    units_held(as_of:) - unsettled_redemption_units(excluding_date_id:)
  end

  # Units this redemption asks for, resolved at a time: all units → held then; amount → amount ÷ NAV per unit.
  # Worked example E34
  def resolved_units(at: Time.zone.today, nav_per_unit_cents: nil)
    return units.to_d if units.present? && !all_units
    return free_units(as_of: at) if all_units

    nav_per_unit_cents ||= FundNav.latest_approved(fund, unit_type, at)&.nav_per_unit_cents
    raise NoNav, "No approved NAV yet — enter units or try after the next NAV is approved" if nav_per_unit_cents.blank?

    (amount_cents.to_d / nav_per_unit_cents.to_d).floor(4)
  end

  # What earlier dealing dates already filled of this order (a part-filled redemption keeps its original
  # request; each date's fill records what was dealt)
  def filled_so_far
    fills = dealing_fills.to_a
    { units: fills.sum { |f| f.units.to_d }, amount_cents: fills.sum { |f| f.amount_cents.to_d } }
  end

  # Part-filled: some of the request was paid out on an earlier date and the rest is queued (F6, F7).
  # A date that carried the whole request (nothing filled) leaves it as asked, so it isn't part-filled
  def part_filled?
    redemption? && open? && dealing_fills.any? { |f| f.units.to_d.positive? }
  end

  # Amount still asked for by an amount-form order (the request less earlier fills); nil for other forms
  def remaining_amount_cents
    return nil unless form == "amount"

    [amount_cents.to_d - filled_so_far[:amount_cents], 0].max
  end

  # Units still asked for: the same "request less earlier fills" the pricer uses (DealingPricer#request_for).
  # All units → free today; amount → remaining amount ÷ NAV per unit (nil without a NAV)
  def remaining_units(nav_per_unit_cents: nil)
    case form
    when "all" then [free_units, 0].max
    when "units" then [units.to_d - filled_so_far[:units], 0].max
    else
      nav_per_unit_cents ||= FundNav.latest_approved(fund, unit_type, Time.zone.today)&.nav_per_unit_cents
      nav_per_unit_cents.to_d.positive? ? (remaining_amount_cents / nav_per_unit_cents.to_d).floor(4) : nil
    end
  end

  def form
    return "all" if all_units
    return "units" if units.present?

    "amount"
  end

  # Worked examples E19, H12: no journey unless the fund wants one for this kind
  def skip_journey?
    !fund.evergreen_fund_setting&.journeys_for?(kind)
  end

  def workflow_url(routes = Rails.application.routes.url_helpers)
    routes.evergreen_order_path(fund_id, id)
  end

  # The investor's signed subscription form (US-14): a document on the investor, named per order
  def subscription_form_name
    "Subscription Form - Order #{id}"
  end

  def subscription_form
    Document.where(owner: investor, name: subscription_form_name).order(:created_at).last
  end

  def to_s
    "#{kind.humanize} #{investor&.investor_name} #{unit_type}"
  end
end
