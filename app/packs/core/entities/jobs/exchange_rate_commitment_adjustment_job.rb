class ExchangeRateCommitmentAdjustmentJob < ApplicationJob
  queue_as :low

  def perform(id)
    Chewy.strategy(:sidekiq) do
      @exchange_rate = ExchangeRate.find(id)
      count = 0
      # Find the commitment with folio_currency
      CapitalCommitment.joins(:fund).where(entity_id: @exchange_rate.entity_id)
                       .where(folio_currency: @exchange_rate.from).where("funds.currency=?", @exchange_rate.to)
                       .each do |cc|
        next unless cc.fund.currency == @exchange_rate.to

        cc.reload

        Rails.logger.debug { "Updating commitment due to exchange_rate for #{cc.investor_name} in #{cc.fund.name}" }

        amount_cents = cc.changed_committed_amount_at_exchange_rate(@exchange_rate.as_of)

        if amount_cents.zero?
          Rails.logger.debug { "No adjustment required for #{cc} for #{@exchange_rate}" }
        else
          reason = "Exchange Rate Changed: #{@exchange_rate}"
          as_of = @exchange_rate.as_of

          ca = CommitmentAdjustment.create!(entity_id: cc.entity_id, fund_id: cc.fund_id, owner: @exchange_rate,
                                            capital_commitment: cc, amount_cents:, reason:, as_of:)
          Rails.logger.debug ca
        end

        count += 1
      end

      Rails.logger.debug { "Updated #{count} commitments due to exchange_rate change" }
    end
    nil
  end
end
