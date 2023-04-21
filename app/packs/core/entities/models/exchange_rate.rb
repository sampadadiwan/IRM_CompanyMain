class ExchangeRate < ApplicationRecord
  include WithFolder
  belongs_to :entity

  scope :latest, -> { where(latest: true) }
  validates :from, :to, :as_of, presence: true
  validates :rate, numericality: { greater_than: 0 }

  before_save :set_latest
  def set_latest
    self.latest = !entity.exchange_rates.where(to:, from:).exists?(["as_of > ?", as_of])
  end

  after_create_commit :ensure_latest
  def ensure_latest
    if latest
      entity.exchange_rates.latest.where(to:, from:).where.not(id:).update(latest: false)
      # Ensure other dependent items get updated with this new exchange rate
      ExchangeRateCommitmentAdjustmentJob.perform_later(id)
    end
  end

  def to_s
    "#{rate} (#{from} -> #{to}) on #{as_of}"
  end

  def folder_path
    "#{entity}/Exchange Rates/#{to_s.delete('->')}"
  end
end
