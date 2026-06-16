class ExchangeRate < ApplicationRecord
  include ExchangeRateShared

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

  def self.ransackable_attributes(_auth_object = nil)
    %w[as_of decimal from latest notes rate to updated_at]
  end

  def self.ransackable_associations(_auth_object = nil)
    []
  end
end
