# One dealing date of an evergreen fund: owns its step bar (a journey evaluated from data), the
# confirmed snapshot, its fills and the links to the settlement records it created.
# Worked examples H16–H21, H26, E23–E34, X17, X18, X20 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingDate < ApplicationRecord
  include ForInvestor
  # The dealing date's step bar is a journey evaluated from its data (DealingDateJourneySetup)
  include Workflowable

  has_journey

  STATUSES = %w[open confirmed closed].freeze

  belongs_to :entity
  belongs_to :fund
  belongs_to :subscription_call, class_name: "CapitalCall", optional: true
  belongs_to :redemption_distribution, class_name: "CapitalDistribution", optional: true
  belongs_to :confirmed_by, class_name: "User", optional: true
  belongs_to :closed_by, class_name: "User", optional: true
  has_many :dealing_orders, dependent: :restrict_with_error
  has_many :dealing_fills, dependent: :destroy

  validates :date, presence: true, uniqueness: { scope: :fund_id }
  validates :cutoff_at, :payment_timing, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :upcoming, ->(from = Time.zone.today) { where(date: from..) }
  scope :confirmed_or_closed, -> { where(status: %w[confirmed closed]) }

  # Find or create the record for a calendar date (from the generate job or the first order).
  # Lock-free: the (fund_id, date) unique index settles a race.
  def self.for(fund, date)
    setting = fund.evergreen_fund_setting
    find_or_create_by!(fund_id: fund.id, date:) do |dd|
      dd.entity_id = fund.entity_id
      dd.cutoff_at = DealingCalendar.cutoff_at(setting, date)
      dd.payment_timing = setting.payment_timing
      dd.has_subscriptions = DealingCalendar.dealing_date?(setting, :subscription, date)
      dd.has_redemptions = DealingCalendar.dealing_date?(setting, :redemption, date)
    end
  rescue ActiveRecord::RecordNotUnique
    find_by!(fund_id: fund.id, date:)
  end

  def open?
    status == "open"
  end

  def confirmed?
    status == "confirmed"
  end

  def closed?
    status == "closed"
  end

  def settled_or_closed?
    %w[confirmed closed].include?(status)
  end

  def pre_funded?
    payment_timing == "before"
  end

  def cutoff_passed?(now = Time.current)
    now > cutoff_at
  end

  # Decision 3 (docs/modules/funds/evergreen_design_decisions.md, agreed 10 Oct 2026): a dealing
  # date may be confirmed only after the LAST deadline for it has passed. Confirming earlier treats
  # an on-time but unpaid pre-funded subscription as "not paid by cut-off", and pushes orders placed
  # before their deadline to the next date. The deadlines are the subscription cut-off (when the date
  # deals subscriptions) and EVERY class's redemption notice deadline (when it deals redemptions) —
  # every class, not only those with orders, because an order for any class can still arrive.
  #
  # Returns [deadline, message] for the latest one, e.g.
  # [Sun 29 Nov 23:59, "Redemption notice for Class B ends 29 November 2026 — confirm after it"]
  def last_deadline
    setting = fund.evergreen_fund_setting
    candidates = []
    # Subscription cut-off: stored on the date when it was generated (settings apply forward only).
    # Also the fallback for a date with neither flag set, so there is always one deadline.
    candidates << [cutoff_at, "Cut-off is #{I18n.l(cutoff_at.to_date, format: :day_month_year)} — confirm after it"] if has_subscriptions || !has_redemptions
    if has_redemptions
      fund.unit_types_list.each do |unit_type|
        deadline = DealingCalendar.notice_deadline(setting, date, unit_type)
        candidates << [deadline, "Redemption notice for Class #{unit_type} ends #{I18n.l(deadline.to_date, format: :day_month_year)} — confirm after it"]
      end
    end
    # Always at least one deadline (a redemption-only date of a fund with no unit types yet): the cut-off
    candidates << [cutoff_at, "Cut-off is #{I18n.l(cutoff_at.to_date, format: :day_month_year)} — confirm after it"] if candidates.empty?
    # The latest DAY wins; on a tie the cut-off (listed first) is named. Comparing exact times would let
    # sub-second noise decide: the stored cut-off is truncated to whole seconds, while a computed notice
    # deadline keeps its microseconds, so a same-day notice deadline would "beat" the cut-off.
    latest_day = candidates.map { |time, _| time.to_date }.max
    message = candidates.find { |time, _| time.to_date == latest_day }.last
    [candidates.map(&:first).max, message]
  end

  # True once every deadline for this date has passed (Decision 3)
  def deadlines_passed?(now = Time.current)
    now > last_deadline.first
  end

  # Why Confirm is blocked by Decision 3, or nil when the deadlines have passed
  def deadline_block_message(now = Time.current)
    deadlines_passed?(now) ? nil : last_deadline.last
  end

  def subscription_fills
    dealing_fills.where(kind: "subscription")
  end

  def redemption_fills
    dealing_fills.where(kind: "redemption")
  end

  # Worked examples X18, E33: nothing may have settled before an undo
  def settlement_started?
    dealing_fills.where.not(fund_unit_id: nil).exists? ||
      dealing_fills.joins(:capital_distribution_payment).exists?(capital_distribution_payments: { completed: true }) ||
      (!pre_funded? && dealing_fills.joins(:capital_remittance).where("capital_remittances.collected_amount_cents > 0").exists?)
  end

  def workflow_url(routes = Rails.application.routes.url_helpers)
    routes.evergreen_dealing_date_path(fund_id, id)
  end

  def to_s
    "#{fund&.name} — #{I18n.l(date)}"
  end
end
