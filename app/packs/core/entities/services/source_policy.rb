# Which rate and price sources a fund (or, for entity-level conversions, the entity) accepts.
# The only place fund/entity flags are turned into sources; FxRateResolver and PriceResolver take
# a policy and never read flags themselves.
#
#   rates:  manual always; market when the entity has Market FX rates AND the fund accepts them;
#           derived when the fund accepts derived rates. own_fund_id when the fund uses its own rates.
#   prices: manual and cost always; market when the entity has Market prices AND the fund accepts them.
#
# The fund is duck-typed (entity, features, id) so core code can use it without depending on funds.
# openspec/changes/fund-market-data — design card ⑤. Worked examples H5, E20, E27, H21.
class SourcePolicy
  attr_reader :rate_sources, :price_sources, :own_fund_id

  def self.for(fund)
    return for_entity(fund) if fund.is_a?(Entity)

    entity = fund.entity
    rates = %w[manual]
    rates << "market" if entity.permissions.enable_market_rates? && fund.features.accept_market_rates?
    rates << "derived" if fund.features.accept_derived_rates?
    prices = %w[manual cost]
    prices << "market" if entity.permissions.enable_market_prices? && fund.features.accept_market_prices?
    own = fund.features.use_own_fx_rates? ? fund.id : nil
    new(rate_sources: rates, price_sources: prices, own_fund_id: own)
  end

  # Entity-level conversions (KPIs, multi-fund reports): the entity's new-fund defaults, never
  # any fund's own rates (E27).
  def self.for_entity(entity)
    defaults = MarketDataSetting.for_entity(entity).fund_default_flags
    rates = %w[manual]
    rates << "market" if entity.permissions.enable_market_rates? && defaults.include?(:accept_market_rates)
    rates << "derived" if defaults.include?(:accept_derived_rates)
    prices = %w[manual cost]
    prices << "market" if entity.permissions.enable_market_prices? && defaults.include?(:accept_market_prices)
    new(rate_sources: rates, price_sources: prices, own_fund_id: nil)
  end

  # Today's behaviour: manual rows only (all existing rows are manual) — used where no fund or
  # entity is known.
  def self.manual_only
    new(rate_sources: %w[manual], price_sources: %w[manual cost], own_fund_id: nil)
  end

  def initialize(rate_sources:, price_sources:, own_fund_id:)
    @rate_sources = rate_sources.freeze
    @price_sources = price_sources.freeze
    @own_fund_id = own_fund_id
  end

  # Direct rate sources (derived rows are only ever built by the resolver)
  def direct_rate_sources
    rate_sources - %w[derived]
  end

  def derived?
    rate_sources.include?("derived")
  end

  # Memo key: two funds with different own rates never share a cached rate
  def key
    "r:#{rate_sources.join('+')}/p:#{price_sources.join('+')}/own:#{own_fund_id || '-'}"
  end

  # "Manual", "Manual, Derived", … — used in the missing-rate message (X9)
  def rate_sources_label
    rate_sources.map(&:capitalize).join(", ")
  end
end
