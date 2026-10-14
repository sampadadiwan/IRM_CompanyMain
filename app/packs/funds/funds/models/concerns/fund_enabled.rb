# Fund-level feature switches, stored as one bitflag integer (`funds.features`) in the same way
# EntityEnabled stores entity features. One place for every fund switch: what the fund shows its
# investors, its reporting options and which market data it accepts.
#
# Add new flags to the END only — inserting in the middle shifts bit positions and corrupts data.
# The first six flags replace the old boolean columns of the same names; the readers/writers below
# keep `fund.show_portfolios` etc. working, backed by the flags (the columns are no longer read).
#
# Worked examples H3, E1–E10, X3 — openspec/changes/fund-market-data/business-rules.md
module FundEnabled
  extend ActiveSupport::Concern

  # The six switches that used to be boolean columns on funds (bit order 0..5 matches the backfill
  # in AddFeaturesToFunds — do not reorder).
  LEGACY_FLAGS = %i[show_fund_ratios show_fund_units show_portfolios show_valuations enable_ai_commentary editable_formulas].freeze

  # The one-off backfill from the old boolean columns (same SQL as the AddFeaturesToFunds migration);
  # kept here so the migration's mapping is exercised by E4.
  LEGACY_BACKFILL_SQL = <<~SQL.squish.freeze
    UPDATE funds SET features =
      (CASE WHEN show_fund_ratios = 1 THEN 1 ELSE 0 END) +
      (CASE WHEN show_fund_units = 1 THEN 2 ELSE 0 END) +
      (CASE WHEN show_portfolios = 1 THEN 4 ELSE 0 END) +
      (CASE WHEN show_valuations = 1 THEN 8 ELSE 0 END) +
      (CASE WHEN enable_ai_commentary = 1 THEN 16 ELSE 0 END) +
      (CASE WHEN editable_formulas = 1 THEN 32 ELSE 0 END)
  SQL

  # Market-data switches and the entity feature each one needs (nil = no entity feature needed).
  MARKET_DATA_FLAGS = {
    accept_market_rates: :enable_market_rates,
    accept_derived_rates: nil,
    accept_market_prices: :enable_market_prices,
    enable_derivatives: :enable_derivatives,
    use_own_fx_rates: nil
  }.freeze

  # The LP portfolio view's two extra switches, appended after the market-data flags (bits 11, 12). They only
  # matter while show_portfolios is on; LpPortfolioView maps the four-option dropdown onto them.
  # Worked examples H5, E3 — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
  LP_PORTFOLIO_FLAGS = %i[lp_folio_portfolio lp_own_share].freeze

  # Switches a new fund starts with, matching the old column defaults (show_fund_units, enable_ai_commentary)
  NEW_FUND_DEFAULTS = %i[show_fund_units enable_ai_commentary].freeze

  included do
    flag :features, LEGACY_FLAGS + %i[accept_market_rates accept_derived_rates accept_market_prices enable_derivatives use_own_fx_rates] + LP_PORTFOLIO_FLAGS

    after_initialize :apply_default_features, if: :new_record?
    after_commit :recompute_fair_values_on_source_change, on: :update

    # Keep the old attribute names working, backed by the flags, so existing callers and uploads
    # (e.g. "show_portfolios=true" in step definitions, ImportFund) read and write the flag.
    LEGACY_FLAGS.each do |name|
      define_method(name) { features.set?(name) }
      define_method(:"#{name}?") { features.set?(name) }
      define_method(:"#{name}=") do |value|
        # Remember the explicit choice so new-fund defaults never override it
        (@explicit_feature_flags ||= Set.new) << name
        ActiveModel::Type::Boolean.new.cast(value) ? features.set(name) : features.unset(name)
      end
    end

    # Assigning the whole set from outside (fund form: an array of names) counts as an explicit choice
    # for every flag. ActiveFlag::Value#set/#unset also call this writer with the Value itself; those
    # single-flag changes are not a whole-set choice. Replaces the writer ActiveFlag defines.
    define_method(:features=) do |arg|
      @explicit_feature_flags = Set.new(Fund.features.keys) unless arg.is_a?(ActiveFlag::Value)
      write_attribute(:features, self.class.active_flags[:features].to_i(arg))
    end
  end

  # True when the fund flag is on AND (for market-data flags) the entity feature it needs is on.
  # A fund bit is kept when the entity feature is later switched off, and simply ignored (E10).
  def feature_enabled?(name)
    return false unless features.set?(name)

    entity_flag = MARKET_DATA_FLAGS[name.to_sym]
    entity_flag.nil? || entity&.permissions&.send(:"#{entity_flag}?")
  end

  private

  # New funds get today's column defaults plus the entity's market-data defaults (E3). A flag the
  # caller set explicitly (fund form, upload, legacy setter) is never overridden.
  def apply_default_features
    explicit = @explicit_feature_flags || Set.new
    NEW_FUND_DEFAULTS.each { |name| features.set(name) unless explicit.include?(name) }
    return unless entity

    # Entity defaults only apply to flags whose entity feature is on
    MarketDataSetting.for_entity(entity).fund_default_flags.each do |name|
      next if explicit.include?(name)

      entity_flag = MARKET_DATA_FLAGS[name]
      features.set(name) if entity_flag.nil? || entity.permissions.send(:"#{entity_flag}?")
    end
  end

  # Changing which rate/price sources a fund accepts changes its current fair values (never booked
  # amounts) — recompute them in the background. E31 — Edge case: changing accepted sources.
  def recompute_fair_values_on_source_change
    change = saved_change_to_features
    return unless change

    before = Fund.features.to_array(change.first.to_i)
    after = Fund.features.to_array(change.last.to_i)
    source_flags = %i[accept_market_rates accept_derived_rates accept_market_prices use_own_fx_rates]
    return if (before & source_flags) == (after & source_flags)

    FundFairValueRecomputeJob.perform_later(id)
  end
end
