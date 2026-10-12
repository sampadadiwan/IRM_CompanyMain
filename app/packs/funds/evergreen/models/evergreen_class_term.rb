# Per-class terms of an evergreen fund. Override columns left null fall back to the fund value
# (EvergreenFundSetting#terms_for).
# Worked examples E4, E5, E42 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenClassTerm < ApplicationRecord
  PERF_FEE_MODELS = %w[none class_hwm].freeze
  HURDLE_TYPES = %w[hard soft].freeze
  CRYSTALLISATIONS = %w[quarterly semi_annual annual].freeze

  include EvergreenCentsAttributes

  cents_attribute :initial_price, :min_initial_subscription, :min_additional_subscription, :min_holding
  # Class-only expense entries are matched by exact name against the ledger, so stray spaces are dropped
  # and a blank becomes nil (evergreen-share-classes H6, X1)
  normalizes :class_expense_entry_name, :class_expense_paid_entry_name, with: ->(name) { name.strip.presence }

  belongs_to :entity
  belongs_to :fund
  belongs_to :evergreen_fund_setting

  validates :unit_type, presence: true, length: { maximum: 40 }, uniqueness: { scope: :fund_id }
  validates :initial_price_cents, numericality: { greater_than: 0 }, allow_nil: true
  validates :perf_fee_model, inclusion: { in: PERF_FEE_MODELS }
  validates :hurdle_type, inclusion: { in: HURDLE_TYPES }
  validates :crystallisation, inclusion: { in: CRYSTALLISATIONS }
  validates :perf_fee_pct, :hurdle_pct, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 50 }
  validates :notice_days, numericality: { in: 0..180 }, allow_nil: true
  validates :lock_up_months, numericality: { in: 0..60 }, allow_nil: true
  validates :lock_up_type, inclusion: { in: EvergreenFundSetting::LOCK_UP_TYPES }, allow_blank: true
  validates :min_initial_subscription_cents, :min_additional_subscription_cents, :min_holding_cents,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate { errors.add(:early_redemption_fee, "must be between 0 and 10%") unless EvergreenFundSetting.valid_early_fee?(early_redemption_fee) }

  # Crystallisation happens on the last day of a quarter, half-year or year.
  # Worked examples H30, E43
  # The NAV dated on the period end — or on its last business day when the end falls on a weekend
  # (review finding: a Friday 29 Sep NAV never crystallised)
  def crystallisation_date?(date)
    period_end = case crystallisation
                 when "quarterly" then date.end_of_quarter
                 when "semi_annual" then date.month <= 6 ? date.change(month: 6).end_of_month : date.end_of_year
                 else date.end_of_year
                 end
    last_business_day = period_end
    last_business_day -= 1.day while last_business_day.saturday? || last_business_day.sunday?
    date.between?(last_business_day, period_end)
  end
end
