class ExchangeRate < ApplicationRecord
  include WithFolder
  belongs_to :entity

  scope :latest, -> { where(latest: true).order(created_at: :asc) }
  validates :from, :to, :as_of, presence: true
  validates :rate, numericality: { greater_than: 0 }
  validates :from, :to, length: { maximum: 5 }
  validates_uniqueness_of :as_of, scope: %i[from to entity_id]

  before_save :set_latest
  def set_latest
    self.latest = !entity.exchange_rates.where(to:, from:).exists?(["as_of > ?", as_of])
  end

  after_create_commit :ensure_latest
  def ensure_latest
    if latest
      entity.exchange_rates.latest.where(to:, from:).where.not(id:).update(latest: false)
      # Ensure other dependent items get updated with this new exchange rate
      if import_upload_id.blank?
        ExchangeRateCommitmentAdjustmentJob.perform_later(id) if entity.customization_flags.enable_exchange_rate_commitment_adjustment?
        ExchangeRatePortfolioInvestmentJob.perform_later(id)
      end
    end
  end

  def to_s
    "#{rate} (#{from} -> #{to}) on #{as_of}"
  end

  def folder_path
    "#{entity}/Exchange Rates/#{to_s.delete('->')}"
  end

  def self.latest_rates_before(end_date, entity_id)
    rates = ExchangeRate
            .where(as_of: ..end_date).where(entity_id: entity_id)
            .order(:from, :to, as_of: :desc)

    latest_rates = rates.group_by { |r| [r.from, r.to] }
                        .transform_values(&:first)

    # Example usage:
    latest_rates.each do |(from, to), rate|
      Rails.logger.debug "#{from} to #{to} => #{rate.rate} (as_of #{rate.as_of})"
    end

    latest_rates
  end

  def self.setup_variable_exchange(as_of, entity_id)
    bank = Money::Bank::VariableExchange.new

    latest_rates = ExchangeRate.latest_rates_before(as_of, entity_id)
    latest_rates.each do |(from, to), rate|
      bank.add_rate(from, to, rate.rate)
    end

    bank
  end

  def self.convert(from, to, amount, as_of, entity_id)
    if from == to
      amount
    else
      er = ExchangeRate.where(from:, to:, as_of: ..as_of, entity_id:).order(as_of: :desc).first
      er.present? ? er.rate * amount : nil
    end
  end

  def self.get_rate(from, to, as_of, entity_id)
    if from == to
      1
    else
      er = ExchangeRate.where(from:, to:, as_of: ..as_of, entity_id:).order(as_of: :desc).first
      er.present? ? er.rate : nil
    end
  end
end
