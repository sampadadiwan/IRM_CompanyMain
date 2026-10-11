# Records corporate actions reported by NSE for the entity's Market instruments on NSE as
# suggestions (ex-dates from the run date to 30 days ahead). The same action is never suggested
# twice, whatever its status (E46, E47); Fund accounting is emailed once per new suggestion.
class CorporateActionFeed
  WINDOW_DAYS = 30

  def self.call(entity:, run_date:)
    new(entity, run_date).call
  end

  def initialize(entity, run_date)
    @entity = entity
    @run_date = run_date
  end

  def call
    instruments = InvestmentInstrument.where(entity_id: @entity.id, pricing_method: "market", exchange: "NSE").where.not(ticker: nil).index_by(&:ticker)
    return [] if instruments.empty?

    actions = NseCorporateActionsProvider.new.actions(instruments.keys, @run_date, @run_date + WINDOW_DAYS)
    actions.filter_map { |action| suggest(instruments[action.ticker], action) }
  rescue MarketDataProvider::Error => e
    Rails.logger.warn { "CorporateActionFeed entity=#{@entity.id}: #{e.message}" }
    []
  end

  private

  def suggest(instrument, action)
    # E47 — Edge case: already suggested (pending, confirmed or dismissed) → nothing new
    return nil if CorporateActionSuggestion.exists?(entity_id: @entity.id, provider_ref: action.ref)

    CorporateActionSuggestion.create!(entity: @entity, investment_instrument: instrument, kind: action.kind, ex_date: action.ex_date,
                                      ratio: action.ratio, amount_per_share_cents: action.amount_per_share && (action.amount_per_share * 100),
                                      currency: instrument.currency, provider: "nse", provider_ref: action.ref, subject: action.subject)
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
