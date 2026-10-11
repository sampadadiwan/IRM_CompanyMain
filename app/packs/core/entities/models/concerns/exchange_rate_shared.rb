module ExchangeRateShared
  extend ActiveSupport::Concern

  # Where a rate came from: typed/uploaded (manual), loaded by a feed (market) or built by
  # FxRateResolver from other rates (derived). openspec fund-market-data — design card ③.
  SOURCES = %w[manual market derived].freeze
  RATE_TYPES = %w[reference closing].freeze

  included do
    include WithFolder

    scope :latest, -> { where(latest: true).order(created_at: :asc) }
    # Entity-wide rates (the default); fund-specific rates carry an owner
    scope :entity_wide, -> { where(owner_type: nil) }
    validates :from, :to, :as_of, presence: true
    validates :rate, numericality: { greater_than: 0 }
    validates :from, :to, length: { maximum: 5 }
    validates :source, inclusion: { in: SOURCES }
    validates :rate_type, inclusion: { in: RATE_TYPES }
    validates :provider, length: { maximum: 40 }
    # One rate per pair, date, source and owner (X8). The DB unique key can't catch duplicate
    # entity-wide rows (NULL owner), so this validation stays authoritative for them.
    validates_uniqueness_of :as_of, scope: %i[from to entity_id owner_type owner_id source]

    before_save :set_latest

    belongs_to :entity
  end

  # `latest` marks the newest rate for the pair within its source and owner
  def set_latest
    self.latest = !self.class.where(entity_id: entity_id, to:, from:, source:, owner_type:, owner_id:).exists?(["as_of > ?", as_of])
  end

  def manual?
    source == "manual"
  end

  def market?
    source == "market"
  end

  def derived?
    source == "derived"
  end

  # "Manual · User", "Market · ECB via EUR", "Derived · via USD" — shown wherever the rate's source is shown
  def source_label
    [source&.capitalize, provider].compact_blank.join(" · ")
  end

  def to_s
    "#{rate} (#{from} -> #{to}) on #{as_of}"
  end

  def folder_path
    "#{entity}/Exchange Rates/#{to_s.delete('->')}"
  end

  class_methods do
    # Latest rate per pair on or before the date, for entity-level reports (Money bank). Only the
    # entity's default sources and entity-wide rows count; manual wins ties (E27).
    def latest_rates_before(end_date, entity_id, policy: nil)
      policy ||= default_policy(entity_id)
      rates =
        where(as_of: ..end_date).where(entity_id: entity_id, owner_type: nil, source: policy.direct_rate_sources)
                                .order(:from, :to, as_of: :desc)
                                .order(Arel.sql(FxRateResolver::SOURCE_RANK_SQL))

      latest_rates = rates.to_a.group_by { |r| [r.from, r.to] }
                          .transform_values(&:first)

      # Example usage:
      latest_rates.each do |(from, to), rate|
        Rails.logger.debug { "#{from} to #{to} => #{rate.rate} (as_of #{rate.as_of})" }
      end

      latest_rates
    end

    def setup_variable_exchange(as_of, entity_id, policy: nil)
      bank = Money::Bank::VariableExchange.new

      latest_rates = latest_rates_before(as_of, entity_id, policy:)
      latest_rates.each do |(from, to), rate|
        bank.add_rate(from, to, rate.rate)
      end

      bank
    end

    # Entity-level conversion. Without a policy it uses the entity's default sources (E27); a fund
    # caller passes SourcePolicy.for(fund).
    def convert(from, to, amount, as_of, entity_id, raise_missing_rate_error: false, policy: nil)
      return amount if from == to

      resolution = FxRateResolver.lookup(entity_id:, from:, to:, as_of:, policy: policy || default_policy(entity_id), model: self)
      raise "Exchange rate not found for #{from} to #{to} as of #{as_of} for entity #{entity_id}" if resolution.nil? && raise_missing_rate_error

      resolution ? resolution.rate * amount : nil
    end

    def get_rate(from, to, as_of, entity_id, policy: nil)
      return 1 if from == to

      FxRateResolver.lookup(entity_id:, from:, to:, as_of:, policy: policy || default_policy(entity_id), model: self)&.rate
    end

    def default_policy(entity_id)
      entity = Entity.find_by(id: entity_id)
      entity ? SourcePolicy.for_entity(entity) : SourcePolicy.manual_only
    end
  end
  # rubocop:enable Metrics/BlockLength
end
