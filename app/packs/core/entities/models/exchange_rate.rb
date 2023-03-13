class ExchangeRate < ApplicationRecord
  belongs_to :entity

  scope :latest, -> { where(latest: true) }

  before_save :set_latest
  def set_latest
    self.latest = !entity.exchange_rates.where(to:, from:).exists?(["as_of > ?", as_of])
  end

  after_create_commit :ensure_latest
  def ensure_latest
    if latest
      entity.exchange_rates.latest.where(to:, from:).where.not(id:).update(latest: false)
      # Ensure other dependent items get updated with this new exchange rate
      ExchangeRateJob.perform_later(id)
    end
  end

  def to_s
    "#{rate} (#{from} -> #{to})"
  end
end
