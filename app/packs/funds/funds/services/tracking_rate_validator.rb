# Checks, before anything is written, that every tracking amount of a fund could be rebuilt in
# new_currency: i.e. that the entity has a fund.currency -> new_currency exchange rate usable for
# every date TrackingCurrencyJob converts at.
#
# One query per source, not per date. WithExchangeRate#get_exchange_rate takes the latest rate
# dated on or before the row's date, for that exact from/to pair (an inverse rate is never used).
# So a rate on or before a source's EARLIEST date is usable for every later date of that source
# too, and "is there any rate as_of <= MIN(date)?" answers the question for the whole source. That
# keeps the check to a MIN() per table, with no row loads, even on account_entries.
#
#   TrackingRateValidator.call(fund, "EUR")
#   # => ["Account Entries: no USD→EUR rate on or before 2021-03-31"]   ([] when all is in place)
class TrackingRateValidator
  # Every date TrackingCurrencyJob#update_fund converts at, as [label, relation, date column].
  # Keep in step with the convert_* methods there.
  def self.sources(fund)
    [
      ["Account Entries", fund.account_entries, :reporting_date],
      ["Remittance Payments", fund.capital_remittance_payments, :payment_date],
      ["Remittances", fund.capital_remittances, :remittance_date],
      ["Distribution Payments", fund.capital_distribution_payments, :payment_date],
      ["Commitment Adjustments", fund.commitment_adjustments, :as_of],
      ["Capital Commitments", fund.capital_commitments, :commitment_date],
      # Default scope (no proforma), like convert_portfolio_investments: proforma rows are never
      # converted, so a rate they would need must not block the change.
      ["Portfolio Investments", fund.portfolio_investments, :investment_date]
    ]
  end

  # @param fund [Fund]
  # @param new_currency [String, nil] blank, or the fund's own currency, needs no rate at all
  # @return [Array<String>] one sentence per source that has no usable rate; empty when the change
  #   can go ahead
  def self.call(fund, new_currency)
    new_currency = new_currency.presence
    return [] if new_currency.nil? || new_currency == fund.currency

    earliest = sources(fund).to_h { |label, relation, column| [label, relation.minimum(column)] }
    earliest["Valuations (tracking FMV)"] = earliest_latest_valuation_date(fund)

    earliest.compact.filter_map do |label, date|
      next if rate_on_or_before?(fund, new_currency, date)

      "#{label}: no #{fund.currency}→#{new_currency} rate on or before #{date}"
    end
  end

  def self.rate_on_or_before?(fund, new_currency, date)
    # Any rate the fund accepts on or before the date, as FxRateResolver would find it (fund-market-data)
    FxRateResolver.lookup(entity_id: fund.entity_id, from: fund.currency, to: new_currency, as_of: date,
                          policy: SourcePolicy.for(fund)).present?
  end

  # TrackingCurrencyJob converts each portfolio investment's FMV at the date of the latest
  # valuation of its instrument (PortfolioComputations#latest_valuation_on(today)). The earliest of
  # those latest dates is the one that needs the oldest rate.
  def self.earliest_latest_valuation_date(fund)
    instrument_ids = fund.portfolio_investments.distinct.pluck(:investment_instrument_id).compact
    return nil if instrument_ids.empty?

    Valuation.where(investment_instrument_id: instrument_ids, valuation_date: ..Time.zone.today)
             .group(:investment_instrument_id).maximum(:valuation_date).values.min
  end

  private_class_method :rate_on_or_before?, :earliest_latest_valuation_date
end
