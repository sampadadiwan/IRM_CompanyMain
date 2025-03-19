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
      ExchangeRateCommitmentAdjustmentJob.perform_later(id) if entity.customization_flags.enable_exchange_rate_commitment_adjustment?
      ExchangeRatePortfolioInvestmentJob.perform_later(id)
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
      puts "#{from} to #{to} => #{rate.rate} (as_of #{rate.as_of})"
    end

    latest_rates
  end
end
