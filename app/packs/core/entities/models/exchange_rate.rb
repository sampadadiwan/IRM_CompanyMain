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
end
