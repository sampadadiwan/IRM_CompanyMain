# Picks the price a fund uses for a holding on a date — the only place price-source precedence
# lives. Candidates: non-synthetic valuations of the instrument for its owner, on or before the
# date, whose source the fund accepts (manual and cost always; market when chosen). Most recent
# wins; on the same date Manual beats Market and Market beats Cost.
#
# openspec/changes/fund-market-data — design card ⑤.
# Worked examples H7, E38–E41 — openspec/changes/fund-market-data/business-rules.md
class PriceResolver
  Resolution = Struct.new(:valuation, :source, :provider, :as_of, :value_cents, :previous_market_value_cents, keyword_init: true)

  class MissingPrice < StandardError
    def initialize(instrument:, as_of:)
      super("No price for #{instrument.name} on or before #{I18n.l(as_of.to_date)}")
    end
  end

  SOURCE_RANK_SQL = "CASE valuations.source WHEN 'manual' THEN 0 WHEN 'market' THEN 1 ELSE 2 END".freeze

  def self.resolve(instrument:, owner:, as_of:, policy:)
    lookup(instrument:, owner:, as_of:, policy:) || raise(MissingPrice.new(instrument:, as_of:))
  end

  def self.lookup(instrument:, owner:, as_of:, policy:)
    scope = Valuation.where(investment_instrument_id: instrument.id, valuation_date: ..as_of.to_date, source: policy.price_sources)
    scope = scope.where(owner:) if owner
    valuation = scope.order(valuation_date: :desc).order(Arel.sql(SOURCE_RANK_SQL)).first
    return nil unless valuation

    Resolution.new(valuation:, source: valuation.source, provider: valuation.provider, as_of: valuation.valuation_date,
                   value_cents: valuation.per_share_value_cents, previous_market_value_cents: previous_market(valuation))
  end

  # The Market price before this one — used for the open-ended NAV's move check (phase 8)
  def self.previous_market(valuation)
    return nil unless valuation.source == "market"

    Valuation.where(investment_instrument_id: valuation.investment_instrument_id, owner: valuation.owner, source: "market")
             .where(valuation_date: ...valuation.valuation_date).order(valuation_date: :desc).pick(:per_share_value_cents)
  end
end
