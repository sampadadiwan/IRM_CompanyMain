# Works out a fund's feature set from what the fund form submitted.
#
# - Only flags the form manages are taken from the request; every other flag keeps its current
#   value (editable_formulas is support-only and edited in admin; a market-data flag whose entity
#   feature is off is not shown, so its bit is kept and ignored — E10).
# - A submitted market-data flag whose entity feature is off is refused (X3 — Error case: direct
#   submission of an unavailable switch).
#
# - The portfolio switches (show_portfolios, show_valuations) work the same way, gated on the fund manager's
#   fund-portfolios module: hidden and kept without it, refused if submitted (E95, X20 —
#   openspec/changes/lp-folio-portfolio-dashboard/business-rules.md).
#
# Worked examples H3, E2, E10, X3 — openspec/changes/fund-market-data/business-rules.md
class FundFeatureGuard
  Result = Struct.new(:features, :refused, keyword_init: true)

  # Flags the fund form always shows
  FORM_FLAGS = %i[show_fund_ratios show_fund_units enable_ai_commentary accept_derived_rates use_own_fx_rates].freeze
  # Flags the form shows only when the fund manager has the fund-portfolios module (E95)
  PORTFOLIO_FLAGS = %i[show_portfolios show_valuations].freeze

  def self.call(fund, requested)
    new(fund).call(requested)
  end

  def initialize(fund)
    @fund = fund
    @entity = fund.entity
  end

  def call(requested)
    requested = Array(requested).compact_blank.map(&:to_sym) & Fund.features.keys
    available = FORM_FLAGS + entity_gated_flags_available + portfolio_flags_available

    # A gated flag submitted while its entity feature is off is refused, not silently dropped
    refused = requested - available - [:editable_formulas]
    refused += [:editable_formulas] if requested.include?(:editable_formulas)

    # Flags the form does not manage keep their current value
    kept = @fund.features.to_a - available
    Result.new(features: ((requested & available) + kept).uniq, refused: refused.uniq)
  end

  # Portfolio flags, when the fund manager has the fund-portfolios module (E95); without it they keep their value
  def portfolio_flags_available
    @entity.permissions.enable_fund_portfolios? ? PORTFOLIO_FLAGS : []
  end

  # Market-data flags whose entity feature is on (these are shown on the form)
  def entity_gated_flags_available
    FundEnabled::MARKET_DATA_FLAGS.filter_map do |flag, entity_flag|
      next if entity_flag.nil?

      flag if @entity.permissions.send(:"#{entity_flag}?")
    end
  end

  # Labels used for the refusal message
  def self.label(flag)
    I18n.t("fund_features.#{flag}", default: flag.to_s.humanize)
  end
end
