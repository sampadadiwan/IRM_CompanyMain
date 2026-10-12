# The currency pairs an entity needs rates for: every other currency it holds or receives into
# each fund currency (instruments, investor folios), plus fund → tracking currency and fund →
# entity currency. Deduplicated in SQL. E12 — Edge case: a new currency is tracked from the next run.
class MarketDataPairsInUse
  def self.for(entity)
    new(entity).pairs
  end

  def initialize(entity)
    @entity = entity
  end

  def pairs
    fund_currencies = Fund.where(entity_id: @entity.id).distinct.pluck(:currency).compact
    others = (InvestmentInstrument.where(entity_id: @entity.id).distinct.pluck(:currency) +
              CapitalCommitment.where(entity_id: @entity.id).distinct.pluck(:folio_currency)).compact.uniq
    tracking = Fund.where(entity_id: @entity.id).where.not(tracking_currency: [nil, ""]).distinct.pluck(:currency, :tracking_currency)

    pairs = fund_currencies.product(others).filter_map { |fund_ccy, other| "#{other}/#{fund_ccy}" if other != fund_ccy }
    pairs += tracking.filter_map { |from, to| "#{from}/#{to}" if from != to }
    pairs += fund_currencies.filter_map { |ccy| "#{ccy}/#{@entity.currency}" if @entity.currency.present? && ccy != @entity.currency }
    pairs.uniq.sort
  end
end
