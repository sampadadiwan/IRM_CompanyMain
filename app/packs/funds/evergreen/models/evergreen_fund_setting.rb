# An evergreen fund's terms. Its existence is the fund's evergreen flag (see EvergreenFund#evergreen?);
# a fund without one is closed-ended and behaves exactly as before.
# Worked examples H1, H2, X2, X3 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenFundSetting < ApplicationRecord
  # Audit trail of settings changes (dealing terms, gates, notification switches)
  audited associated_with: :fund
  CALENDARS = %w[monthly quarterly semi_annual annual custom].freeze
  DEALING_DAYS = %w[first last day_n].freeze
  PAYMENT_TIMINGS = %w[before after].freeze
  UNREADY_HANDLING = %w[roll cancel].freeze
  ORDER_JOURNEYS = %w[off subscriptions both].freeze
  REDEMPTION_FORMS = %w[units amount all].freeze
  LOCK_UP_TYPES = %w[hard soft].freeze
  GATE_LEVELS = %w[fund class].freeze
  GATE_PERIODS = %w[dealing_date quarter year].freeze
  GATE_METHODS = %w[fifo pro_rata].freeze

  include EvergreenCentsAttributes

  # ---- Notifications (open-ended-funds § Notifications) ----
  # key => [audience, default on?, label, recipients, description]. Missing keys in `notifications` use
  # these defaults, so a notification added later only needs a row here.
  NOTIFICATIONS = {
    "payment_reminder" => [:investor, true, "Payment reminder", "Investor users and approved advisors", "Pre-funded subscriptions still unpaid a few days before the cut-off."],
    "action_needed" => [:investor, true, "Action needed", "Investor users and approved advisors", "Orders whose journey is not finished a few days before the cut-off — names the pending step."],
    "payment_received" => [:investor, true, "Payment received", "Investor users and approved advisors", "Confirms a subscription payment once it is recorded and verified."],
    "units_unlocked" => [:investor, false, "Units free to redeem", "Investor users and approved advisors", "The day a lock-up ends for units the investor holds."],
    "nav_update" => [:investor, false, "Monthly NAV update", "Investor users and approved advisors", "On each approved NAV: NAV per unit and the investor's holding value."],
    "new_order" => [:internal, true, "New order received", "Relationship manager (Managed by), else Fund ops", "An investor places an order on the portal."],
    "nav_awaiting_approval" => [:internal, true, "NAV awaiting approval", "Approvers (not the preparer)", "A NAV is drafted or uploaded."],
    "nav_approved" => [:internal, true, "NAV approved", "Preparer and Fund ops", "A NAV is approved."],
    "cutoff_summary" => [:internal, true, "Cut-off summary", "Fund ops", "The day after a cut-off: orders in, unpaid, not ready, and what will roll."],
    "ready_to_confirm" => [:internal, true, "Ready to confirm", "Fund ops and approvers", "The NAV is approved and the cut-off has passed."],
    "gate_applied" => [:internal, true, "Gate applied", "Compliance and Fund ops", "A dealing date is confirmed with redemptions carried forward."],
    "large_redemption" => [:internal, true, "Large redemption", "Compliance and relationship manager", "A redemption at or above the threshold below (% of class NAV)."],
    "settlement_overdue" => [:internal, true, "Settlement overdue", "Fund ops", "Redemptions unpaid after their due date; pay-after money not in after the pay-by date."],
    "documents_awaiting_approval" => [:internal, true, "Documents awaiting approval", "Approvers", "Contract notes or redemption advices were generated from the fund's templates and wait for Approve & send."],
    "fee_accrual_behind" => [:internal, true, "Fee accrual behind", "Fund accounting", "A NAV is drafted while the management fee is accrued only to an earlier date."]
  }.freeze
  NOTIFICATION_NUMBERS = { "reminder_days" => 2, "large_redemption_pct" => 2 }.freeze

  validate :notification_numbers_in_range

  def notify?(key)
    value = notifications.to_h[key.to_s]
    value.nil? ? NOTIFICATIONS.fetch(key.to_s)[1] : ActiveModel::Type::Boolean.new.cast(value)
  end

  def notification_number(key)
    (notifications.to_h[key.to_s].presence || NOTIFICATION_NUMBERS.fetch(key.to_s)).to_d
  end

  # Reminder days 1–30 (whole days); large-redemption threshold above 0 and at most 100 (X21, X22)
  def notification_numbers_in_range
    days = notifications.to_h["reminder_days"]
    errors.add(:base, "Reminder days must be between 1 and 30") if days.present? && !(days.to_s.match?(/\A\d+\z/) && days.to_i.between?(1, 30))
    pct = notifications.to_h["large_redemption_pct"]
    errors.add(:base, "Large redemption threshold must be above 0 and at most 100") if pct.present? && !(pct.to_s.to_d.positive? && pct.to_s.to_d <= 100)
  end

  cents_attribute :min_initial_subscription, :min_additional_subscription, :min_holding

  belongs_to :entity
  belongs_to :fund
  attr_readonly :fund_id # never moves to another fund (funds_api_security_policy_plan.md, B)
  belongs_to :enabled_by, class_name: "User", optional: true
  belongs_to :subscription_journey_template, class_name: "WorkflowTemplate", optional: true
  belongs_to :redemption_journey_template, class_name: "WorkflowTemplate", optional: true
  belongs_to :contract_note_template, class_name: "Document", optional: true
  belongs_to :redemption_advice_template, class_name: "Document", optional: true
  has_many :evergreen_class_terms, dependent: :destroy

  accepts_nested_attributes_for :evergreen_class_terms

  # Defaults for JSON columns (MySQL can't default JSON in the schema)
  after_initialize :set_json_defaults, if: :new_record?

  validates :subscription_calendar, :redemption_calendar, inclusion: { in: CALENDARS }
  validates :dealing_day, inclusion: { in: DEALING_DAYS }
  validates :dealing_day_n, numericality: { in: 1..28 }, if: -> { dealing_day == "day_n" }
  validates :payment_timing, inclusion: { in: PAYMENT_TIMINGS }
  validates :pay_after_days, numericality: { in: 1..30 }
  validates :subscription_cutoff_days, numericality: { in: 0..30 }
  validates :unready_handling, inclusion: { in: UNREADY_HANDLING }
  validates :order_journeys, inclusion: { in: ORDER_JOURNEYS }
  validates :redemption_settlement_days, numericality: { in: 1..90 }
  validates :notice_days, numericality: { in: 0..180 }
  validates :lock_up_months, numericality: { in: 0..60 }
  validates :lock_up_type, inclusion: { in: LOCK_UP_TYPES }
  validates :gate_level, inclusion: { in: GATE_LEVELS }
  # What this fund's investors hold, when it differs from the entity's wording (blank = Units). Wording only.
  validates :unit_term, inclusion: { in: EvergreenLabels::UNIT_TERMS }, allow_blank: true
  validates :gate_period, inclusion: { in: GATE_PERIODS }
  validates :gate_method, inclusion: { in: GATE_METHODS }
  validates :gate_pct, :investor_gate_pct, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100, message: "must be between 0 and 100" }
  validates :min_initial_subscription_cents, :min_additional_subscription_cents, :min_holding_cents, numericality: { greater_than_or_equal_to: 0 }
  validates :cash_entry_name, :other_assets_entry_name, :other_liabilities_entry_name,
            :mgmt_fee_paid_entry_name, :perf_fee_paid_entry_name, presence: true, length: { maximum: 125 }
  validates :fund_close_name, presence: true, length: { maximum: 255 }
  validates :fund_id, uniqueness: true
  validate :at_least_one_redemption_form
  validate :custom_dates_present
  validate :early_fee_shape
  validate :class_expense_entries
  validate :class_starting_prices, on: :create

  # Worked example X3: a fund must accept at least one way to redeem
  def at_least_one_redemption_form
    forms = Array(redemption_forms).compact_blank
    errors.add(:base, "Allow at least one way to redeem") if forms.empty?
    errors.add(:redemption_forms, "contains an unknown form") if (forms - REDEMPTION_FORMS).any?
  end

  def custom_dates_present
    errors.add(:subscription_dates, "must list at least one date") if subscription_calendar == "custom" && Array(subscription_dates).compact_blank.empty?
    errors.add(:redemption_dates, "must list at least one date") if redemption_calendar == "custom" && Array(redemption_dates).compact_blank.empty?
  end

  def early_fee_shape
    errors.add(:early_redemption_fee, "must be between 0 and 10%") unless EvergreenFundSetting.valid_early_fee?(early_redemption_fee)
  end

  # evergreen-fund-on-create X2: every class needs a starting price when the fund is created open-ended —
  # it prices the class's first subscriptions until the class has an approved NAV
  def class_starting_prices
    evergreen_class_terms.sort_by(&:unit_type).each do |term|
      next if term.initial_price_cents.to_d.positive?

      errors.add(:base, "Class #{term.unit_type} needs a starting price")
    end
  end

  LEDGER_NAME_FIELDS = %i[cash_entry_name other_assets_entry_name other_liabilities_entry_name
                          mgmt_fee_paid_entry_name perf_fee_paid_entry_name].freeze

  # Each class may name its own expense entries — both or neither, its own, never a fund ledger
  # setting — and may not drop them while its latest NAV still carries class expenses.
  # Worked examples X1–X5, X7 — openspec/changes/evergreen-share-classes/design.md#worked-examples
  def class_expense_entries
    fund_names = LEDGER_NAME_FIELDS.map { |f| self[f].to_s.strip.downcase }
    owners = {}
    evergreen_class_terms.sort_by(&:unit_type).each do |term|
      names = [term.class_expense_entry_name, term.class_expense_paid_entry_name].map { |n| n.to_s.strip }
      label = "Class #{term.unit_type}"
      # X5: clearing both while the latest NAV still shows class expenses payable
      if names.all?(&:blank?)
        check_class_expenses_cleared(term, label)
        next
      end
      # X1: one without the other
      if names.any?(&:blank?)
        errors.add(:base, "#{label} needs both a class expenses entry and a class expenses paid entry, or neither")
        next
      end
      # X4: same limit as the fund's own ledger-name settings
      if names.first.length > 125
        errors.add(:base, "Class expenses entry is too long (maximum is 125 characters)")
        next
      end
      if names.last.length > 125
        errors.add(:base, "Class expenses paid entry is too long (maximum is 125 characters)")
        next
      end
      # X7: the expense and its payment must be two different entries, or the payable never moves
      if names.first.casecmp?(names.last)
        errors.add(:base, "#{label}'s class expenses entry and class expenses paid entry must be different")
        next
      end
      names.each do |name|
        # X3: a fund ledger setting is shared by every class
        if fund_names.include?(name.downcase)
          errors.add(:base, "#{label}'s expense entry '#{name}' is already one of the fund's ledger settings")
        # X2: one class owns an entry, or it would be counted twice
        elsif (other = owners[name.downcase])
          errors.add(:base, "#{label}'s expense entry '#{name}' is already used by #{other} — each class needs its own entries")
        else
          owners[name.downcase] = label
        end
      end
    end
  end

  # X5: refuse removing a class's expense entries while its latest NAV still carries a payable
  def check_class_expenses_cleared(term, label)
    return unless term.persisted? && term.class_expense_entry_name_was.present?

    owed = FundNav.where(fund_id:, unit_type: term.unit_type).order(nav_date: :desc).pick(:class_expenses_payable_cents).to_d
    return if owed.zero?

    money = ApplicationController.helpers.money_to_currency(Money.new(owed, fund&.currency || "INR"))
    errors.add(:base, "#{label} still owes #{money} of class expenses on its latest NAV — pay or reverse it before removing its expense entries")
  end

  # Shared with EvergreenClassTerm: {"pct": x} or {"schedule": [{"from","to","pct"}]}, every pct 0–10
  def self.valid_early_fee?(fee)
    return true if fee.blank?

    pcts = fee["schedule"].present? ? fee["schedule"].pluck("pct") : [fee["pct"]]
    pcts.all? { |p| p.to_d.between?(0, 10) }
  end

  def redemption_form_allowed?(form)
    Array(redemption_forms).include?(form)
  end

  def pre_funded?
    payment_timing == "before"
  end

  def journeys_for?(kind)
    order_journeys == "both" || (order_journeys == "subscriptions" && kind.to_s == "subscription")
  end

  # The effective terms for a class: the class override where present, else the fund value.
  # Lazily creates the class row (with no overrides) the first time a class is used.
  # Worked example E4
  def terms_for(unit_type)
    raise ArgumentError, "#{unit_type} is not a unit class of #{fund.name}" unless fund.unit_types_list.to_a.include?(unit_type.to_s)

    term = class_term_for(unit_type)
    EvergreenTerms.new(
      unit_type: unit_type.to_s,
      notice_days: term.notice_days || notice_days,
      lock_up_months: term.lock_up_months || lock_up_months,
      lock_up_type: term.lock_up_type.presence || lock_up_type,
      early_redemption_fee: term.early_redemption_fee.presence || early_redemption_fee,
      min_initial_subscription_cents: term.min_initial_subscription_cents || min_initial_subscription_cents,
      min_additional_subscription_cents: term.min_additional_subscription_cents || min_additional_subscription_cents,
      min_holding_cents: term.min_holding_cents || min_holding_cents,
      initial_price_cents: term.initial_price_cents,
      perf_fee_model: term.perf_fee_model,
      perf_fee_pct: term.perf_fee_pct,
      hurdle_pct: term.hurdle_pct,
      hurdle_type: term.hurdle_type,
      crystallisation: term.crystallisation,
      class_expense_entry_name: term.class_expense_entry_name.presence,
      class_expense_paid_entry_name: term.class_expense_paid_entry_name.presence
    )
  end

  def class_term_for(unit_type)
    evergreen_class_terms.find { |t| t.unit_type == unit_type.to_s } ||
      evergreen_class_terms.create!(entity_id:, fund_id:, unit_type: unit_type.to_s)
  end

  private

  def set_json_defaults
    self.redemption_forms ||= REDEMPTION_FORMS.dup
    self.early_redemption_fee ||= { "pct" => 0 }
  end
end
