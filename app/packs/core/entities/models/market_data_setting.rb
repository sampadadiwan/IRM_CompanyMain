# Market Data settings. One entity row (fund_id nil) holds the feeds, the cross-rate pivot currency,
# the defaults a new fund starts with and the default NAV limits. A fund row (fund_id set) only
# overrides the limits for that fund; a blank limit on the fund row falls back to the entity row.
#
# openspec/changes/fund-market-data — design card ① Switches.
# Worked examples H2, E7, E9, X2, X4, X5 — openspec/changes/fund-market-data/business-rules.md
class MarketDataSetting < ApplicationRecord
  include Trackable.new(associated_with: :entity)

  # Free public sources only in this change; licensed vendors are added per client later (L4)
  FX_PROVIDERS = %w[ecb].freeze
  PRICE_PROVIDERS = %w[nse bse amfi nse_fo].freeze

  # Defaults used when neither the fund row nor the entity row sets a limit
  DEFAULT_MAX_RATE_AGE_DAYS = 3
  DEFAULT_MAX_PRICE_AGE_DAYS = 3
  DEFAULT_PRICE_MOVE_THRESHOLD_PCT = 10

  Limits = Struct.new(:max_rate_age_days, :max_price_age_days, :price_move_threshold_pct, keyword_init: true)

  belongs_to :entity
  belongs_to :fund, optional: true

  # The entity row is unique per entity; MySQL allows repeated NULL fund_ids in the unique index,
  # so the entity row's uniqueness is also checked here.
  validates :fund_id, uniqueness: { scope: :entity_id }
  validates :pivot_currency, presence: true, length: { maximum: 5 }
  validates :max_rate_age_days, :max_price_age_days,
            numericality: { only_integer: true, in: 0..30, message: "must be between 0 and 30" }, allow_nil: true
  validates :price_move_threshold_pct,
            numericality: { in: 1..100, message: "must be between 1 and 100" }, allow_nil: true
  validate :providers_chosen_when_feed_on
  validate :providers_known

  before_validation :clean_provider_lists
  # A fund row (limit overrides, built from the fund form) belongs to the fund's entity
  before_validation { self.entity_id ||= fund&.entity_id }

  # The entity's row, or an unsaved one with the built-in defaults when the entity has none yet.
  def self.for_entity(entity)
    find_by(entity_id: entity.id, fund_id: nil) ||
      new(entity:, fund_id: nil, max_rate_age_days: DEFAULT_MAX_RATE_AGE_DAYS,
          max_price_age_days: DEFAULT_MAX_PRICE_AGE_DAYS,
          price_move_threshold_pct: DEFAULT_PRICE_MOVE_THRESHOLD_PCT, fund_defaults: {})
  end

  # Effective limits for a fund: fund row ?? entity row ?? built-in default, per limit (E7).
  def self.limits_for(fund)
    entity_row = for_entity(fund.entity)
    fund_row = fund.market_data_setting
    pick = ->(attr, default) { fund_row&.public_send(attr) || entity_row.public_send(attr) || default }
    Limits.new(max_rate_age_days: pick.call(:max_rate_age_days, DEFAULT_MAX_RATE_AGE_DAYS),
               max_price_age_days: pick.call(:max_price_age_days, DEFAULT_MAX_PRICE_AGE_DAYS),
               price_move_threshold_pct: pick.call(:price_move_threshold_pct, DEFAULT_PRICE_MOVE_THRESHOLD_PCT))
  end

  def entity_row?
    fund_id.nil?
  end

  # Market-data fund flags a new fund starts with (only flags FundEnabled knows about)
  def fund_default_flags
    (fund_defaults || {}).select { |_, on| ActiveModel::Type::Boolean.new.cast(on) }
                         .keys.map(&:to_sym) & FundEnabled::MARKET_DATA_FLAGS.keys
  end

  private

  # Forms send arrays with a blank first value; keep only real provider keys
  def clean_provider_lists
    self.fx_providers = Array(fx_providers).compact_blank
    self.price_providers = Array(price_providers).compact_blank
  end

  # X2 — Error case: a feed switched on with no provider ticked
  def providers_chosen_when_feed_on
    errors.add(:fx_providers, "Choose at least one provider") if fx_feed_enabled && fx_providers.blank?
    errors.add(:price_providers, "Choose at least one provider") if price_feed_enabled && price_providers.blank?
  end

  def providers_known
    errors.add(:fx_providers, "has an unknown provider") if (Array(fx_providers) - FX_PROVIDERS).any?
    errors.add(:price_providers, "has an unknown provider") if (Array(price_providers) - PRICE_PROVIDERS).any?
  end
end
