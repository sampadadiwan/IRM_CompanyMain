# Whether a fund's market data is in place for an allocation run ending on end_date: portfolio
# valuations and FX rates dated within n_days before it.
#
# Two callers, one set of rules:
#   - AllocationRunRuleContextProvider, for the entity-level validation rules checked when an
#     allocation is submitted (allocation_run_valuation_exists, allocation_run_fx_rates_exist);
#   - AccountEntryAllocation::CheckHelpers#valuations_present / #fx_rates_present, for a fund's
#     own pre-run checks, which need the rows rather than a sentence.
# Keeping the queries here stops the two from drifting into different answers for the same fund.
class AllocationRunReadiness
  # @param fund [Fund]
  # @param entity_id [Integer] whose exchange rates to look in
  # @param end_date [Date]
  # @param n_days [Integer] how far before end_date a valuation or rate may be dated
  def initialize(fund:, entity_id:, end_date:, n_days:)
    @fund = fund
    @entity_id = entity_id
    @end_date = end_date
    @n_days = n_days.to_i
  end

  def since = @end_date - @n_days.days

  # Portfolio companies the fund holds a position in (positive net quantity as of end_date) that
  # have no valuation within [end_date - n_days, end_date]. Fully exited or not-yet-invested
  # companies are left out.
  # @return [Array<Array(Integer, String)>, nil] [investor id, name] pairs; nil when the fund has
  #   no active position at all (nothing to check), [] when every company is valued
  def missing_valuation_companies
    pc_ids = PortfolioInvestment.where(fund_id: @fund.id)
                                .where(investment_date: ..@end_date)
                                .group(:portfolio_company_id)
                                .having("SUM(quantity) > 0")
                                .pluck(:portfolio_company_id)
    return nil if pc_ids.empty?

    valued_ids = Valuation.unscoped
                          .where(owner_type: "Investor", owner_id: pc_ids)
                          .where(valuation_date: since..@end_date)
                          .distinct
                          .pluck(:owner_id)
                          .to_set

    missing_ids = pc_ids.reject { |id| valued_ids.include?(id) }
    return [] if missing_ids.empty?

    Investor.where(id: missing_ids).pluck(:id, :investor_name)
  end

  # The latest valuation dated on or before end_date for each company, for saying how stale.
  # @return [Hash{Integer => Date}]
  def latest_valuation_dates(company_ids)
    Valuation.unscoped.where(owner_type: "Investor", owner_id: company_ids, valuation_date: ..@end_date)
             .group(:owner_id).maximum(:valuation_date)
  end

  # Currency pairs the fund needs a rate for, with who needs each, that have no rate within
  # [end_date - n_days, end_date]. Pairs come from:
  #   instruments -- instrument.currency -> fund.currency, labelled by instrument name
  #   feeders     -- feeder.currency -> fund.currency, labelled "feeder: <name>"
  #   tracking    -- fund.currency -> fund.tracking_currency, labelled "tracking currency"
  # @return [Hash{Array(String, String) => Array<String>}, nil] nil when the fund needs no rate at
  #   all, {} when every needed rate is present
  def missing_fx_rates
    sources = fx_rate_sources
    return nil if sources.empty?

    sources.reject do |(from, to), _|
      ExchangeRate.where(entity_id: @entity_id, from:, to:).exists?(as_of: since..@end_date)
    end
  end

  # Every currency pair the fund needs a rate for, whether or not one exists, and what needs it.
  # Shared with the run check suggester, which suggests an FX rate check only for a fund that has one.
  # @return [Hash{Array(String, String) => Array<String>}] empty when the fund needs no rate
  def fx_rate_sources
    sources = Hash.new { |h, k| h[k] = [] }

    @fund.investment_instruments
         .reject { |i| i.currency.blank? || i.currency == @fund.currency }
         .group_by(&:currency)
         .each do |currency, instruments|
      sources[[currency, @fund.currency]].concat(instruments.map(&:name).uniq)
    end

    @fund.feeder_funds
         .reject { |f| f.currency.blank? || f.currency == @fund.currency }
         .group_by(&:currency)
         .each do |currency, feeders|
      sources[[currency, @fund.currency]].concat(feeders.map { |f| "feeder: #{f.name}" }.uniq)
    end

    sources[[@fund.currency, @fund.tracking_currency]] << "tracking currency" if @fund.has_tracking_currency?
    sources.to_h
  end

  # The latest rate dated on or before end_date for a pair, for saying how stale.
  # @return [Date, nil]
  def latest_fx_rate_date(from, to)
    ExchangeRate.where(entity_id: @entity_id, from:, to:, as_of: ..@end_date).maximum(:as_of)
  end
end
