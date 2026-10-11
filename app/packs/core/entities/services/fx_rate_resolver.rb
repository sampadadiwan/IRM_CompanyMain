# Picks the exchange rate a fund (or entity) uses for a pair on a date — the only place source
# precedence and derivation live. Every conversion goes through here.
#
#   1. Candidates: entity-wide rates whose source the policy accepts, plus the fund's own manual
#      rates when the policy names one (never another fund's, never another entity's).
#   2. Direct rate: the most recent on or before the date; same date → fund's own > manual > market.
#   3. If the policy accepts derived rates: the reverse of the opposite pair (1 / rate) and the
#      cross through the entity's pivot currency (from→pivot × pivot→to), built from direct rates
#      only. A derived rate's date is the older of its legs.
#   4. Most recent of direct / reverse / cross wins; same date → direct > reverse > cross.
#   5. A derived result is stored as a `derived` ExchangeRate (owner = the fund when a fund-own leg
#      was used) so converted records can point at the rate they used; it is updated in place when
#      its legs change.
#
# openspec/changes/fund-market-data — design card ⑤.
# Worked examples H5, H21, E18–E28, E68–E71, X9, X10 — business-rules.md
class FxRateResolver
  Resolution = Struct.new(:rate, :source, :provider, :as_of, :row, :kind, :owner_fund_id, keyword_init: true) do
    def row_id
      row&.id
    end
  end

  # Raised when no accepted rate exists; the message is what the user sees (X9)
  class MissingRate < StandardError
    attr_reader :from, :to, :as_of

    def initialize(from:, to:, as_of:, policy:)
      @from = from
      @to = to
      @as_of = as_of
      super("No #{from}→#{to} rate on or before #{I18n.l(as_of.to_date)} in this fund's accepted sources " \
            "(#{policy.rate_sources_label}). Enter a manual rate, or accept derived rates for this fund.")
    end
  end

  # Same-date order: fund's own rate first, then manual, then market (portable across MySQL/SQLite)
  OWNER_RANK_SQL = "CASE WHEN owner_id IS NULL THEN 1 ELSE 0 END".freeze
  SOURCE_RANK_SQL = "CASE source WHEN 'manual' THEN 0 WHEN 'market' THEN 1 ELSE 2 END".freeze
  KIND_RANK = { direct: 0, reverse: 1, cross: 2 }.freeze

  class << self
    # Resolution, or MissingRate
    def resolve(entity_id:, from:, to:, as_of:, policy:, model: ExchangeRate)
      lookup(entity_id:, from:, to:, as_of:, policy:, model:) ||
        raise(MissingRate.new(from:, to:, as_of:, policy:))
    end

    # Resolution, or nil when no accepted rate exists
    def lookup(entity_id:, from:, to:, as_of:, policy:, model: ExchangeRate)
      # E26 — Edge case: same currency needs no lookup
      return Resolution.new(rate: 1, source: "manual", provider: nil, as_of:, kind: :direct) if from == to

      key = [model.name, entity_id, policy.key, from, to, as_of.to_date]
      cache = Thread.current[:fx_rate_resolver_cache]
      return cache[key] if cache&.key?(key)

      result = new(entity_id:, policy:, model:).call(from, to, as_of.to_date)
      cache[key] = result if cache
      result
    end

    # Memoises lookups for the duration of the block (jobs and requests that convert many amounts)
    def with_cache
      outer = Thread.current[:fx_rate_resolver_cache]
      Thread.current[:fx_rate_resolver_cache] ||= {}
      yield
    ensure
      Thread.current[:fx_rate_resolver_cache] = outer
    end
  end

  def initialize(entity_id:, policy:, model:)
    @entity_id = entity_id
    @policy = policy
    @model = model
  end

  def call(from, to, as_of)
    candidates = []
    direct = best_direct(from, to, as_of)
    candidates << { kind: :direct, rate: direct.rate, as_of: direct.as_of, legs: [direct] } if direct

    if @policy.derived?
      # E22 — Edge case: reverse rate
      reverse = best_direct(to, from, as_of)
      candidates << { kind: :reverse, rate: (1 / reverse.rate.to_d).round(8), as_of: reverse.as_of, legs: [reverse] } if reverse

      # E21 — Edge case: cross through the pivot from accepted legs only (X10 when a leg isn't accepted)
      pivot = pivot_currency
      if pivot && from != pivot && to != pivot
        leg1 = best_direct(from, pivot, as_of)
        leg2 = leg1 && best_direct(pivot, to, as_of)
        if leg1 && leg2
          candidates << { kind: :cross, rate: (leg1.rate.to_d * leg2.rate.to_d).round(8),
                          as_of: [leg1.as_of, leg2.as_of].min, legs: [leg1, leg2], pivot: }
        end
      end
    end
    return nil if candidates.empty?

    # E23 — Edge case: the most recent wins, even a derived over an older direct; ties go direct > reverse > cross
    best = candidates.max_by { |c| [c[:as_of], -KIND_RANK[c[:kind]]] }
    best[:kind] == :direct ? direct_resolution(best[:legs].first) : derived_resolution(from, to, best)
  end

  private

  # Most recent direct rate for the pair among accepted sources (and the fund's own rates)
  def best_direct(from, to, as_of)
    scope = @model.where(entity_id: @entity_id, from:, to:).where(as_of: ..as_of)
    accepted = scope.where(owner_type: nil, source: @policy.direct_rate_sources)
    # H21 — fund-specific rates count only for their own fund, and only while it uses them
    accepted = accepted.or(scope.where(owner_type: "Fund", owner_id: @policy.own_fund_id, source: "manual")) if @policy.own_fund_id
    accepted.order(as_of: :desc).order(Arel.sql(OWNER_RANK_SQL)).order(Arel.sql(SOURCE_RANK_SQL)).first
  end

  def direct_resolution(row)
    Resolution.new(rate: row.rate, source: row.source, provider: row.provider, as_of: row.as_of, row:,
                   kind: :direct, owner_fund_id: row.owner_type == "Fund" ? row.owner_id : nil)
  end

  # Stores (or refreshes) the derived row so converted records can point at it (E24)
  def derived_resolution(from, to, candidate)
    legs = candidate[:legs]
    owner_id = legs.filter_map { |l| l.owner_type == "Fund" ? l.owner_id : nil }.first
    provider = candidate[:kind] == :reverse ? "reverse" : "via #{candidate[:pivot]}"
    row = store_derived(from, to, candidate, legs, owner_id, provider)
    Resolution.new(rate: candidate[:rate], source: "derived", provider:, as_of: candidate[:as_of], row:,
                   kind: candidate[:kind], owner_fund_id: owner_id)
  end

  def store_derived(from, to, candidate, legs, owner_id, provider)
    attrs = { entity_id: @entity_id, from:, to:, as_of: candidate[:as_of], source: "derived",
              owner_type: owner_id ? "Fund" : nil, owner_id: }
    leg_ids = { leg1_id: legs[0]&.id, leg2_id: legs[1]&.id }
    # The allocation engine's scratch SQLite copy is throwaway: build the derived rate, don't store it
    return @model.new(attrs.merge(rate: candidate[:rate], provider:, rate_type: "reference", **leg_ids)) unless @model == ExchangeRate

    row = @model.find_by(attrs)
    if row
      # Legs or rate changed since it was stored: refresh in place, without callbacks
      row.update_columns(rate: candidate[:rate], provider:, **leg_ids, updated_at: Time.current) if row.rate.to_d != candidate[:rate] || row.leg1_id != leg_ids[:leg1_id] || row.leg2_id != leg_ids[:leg2_id]
      return row
    end

    @model.create!(attrs.merge(rate: candidate[:rate], provider:, rate_type: "reference", **leg_ids,
                               notes: "Built from #{legs.join(' and ')}"))
  rescue ActiveRecord::RecordNotUnique
    # Another request stored it first
    @model.find_by(attrs)
  end

  def pivot_currency
    entity = Entity.find_by(id: @entity_id)
    entity && MarketDataSetting.for_entity(entity).pivot_currency
  end
end
