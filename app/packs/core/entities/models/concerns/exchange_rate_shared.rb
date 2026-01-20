module ExchangeRateShared
  extend ActiveSupport::Concern

  included do
    include WithFolder

    scope :latest, -> { where(latest: true).order(created_at: :asc) }
    validates :from, :to, :as_of, presence: true
    validates :rate, numericality: { greater_than: 0 }
    validates :from, :to, length: { maximum: 5 }
    validates_uniqueness_of :as_of, scope: %i[from to entity_id]

    before_save :set_latest

    belongs_to :entity
  end

  def set_latest
    self.latest = !self.class.where(entity_id: entity_id, to:, from:).exists?(["as_of > ?", as_of])
  end

  def to_s
    "#{rate} (#{from} -> #{to}) on #{as_of}"
  end

  def folder_path
    "#{entity}/Exchange Rates/#{to_s.delete('->')}"
  end

  class_methods do
    def latest_rates_before(end_date, entity_id)
      rates =
        where(as_of: ..end_date).where(entity_id: entity_id)
                                .order(:from, :to, as_of: :desc)

      latest_rates = rates.to_a.group_by { |r| [r.from, r.to] }
                          .transform_values(&:first)

      # Example usage:
      latest_rates.each do |(from, to), rate|
        Rails.logger.debug "#{from} to #{to} => #{rate.rate} (as_of #{rate.as_of})"
      end

      latest_rates
    end

    def setup_variable_exchange(as_of, entity_id)
      bank = Money::Bank::VariableExchange.new

      latest_rates = latest_rates_before(as_of, entity_id)
      latest_rates.each do |(from, to), rate|
        bank.add_rate(from, to, rate.rate)
      end

      bank
    end

    def convert(from, to, amount, as_of, entity_id, raise_missing_rate_error: false)
      if from == to
        amount
      else
        er = where(from:, to:, as_of: ..as_of, entity_id:).order(as_of: :desc).first

        raise "Exchange rate not found for #{from} to #{to} as of #{as_of} for entity #{entity_id}" if er.nil? && raise_missing_rate_error

        er.present? ? er.rate * amount : nil
      end
    end

    def get_rate(from, to, as_of, entity_id)
      if from == to
        1
      else
        er = where(from:, to:, as_of: ..as_of, entity_id:).order(as_of: :desc).first
        er.presence&.rate
      end
    end
  end
end
