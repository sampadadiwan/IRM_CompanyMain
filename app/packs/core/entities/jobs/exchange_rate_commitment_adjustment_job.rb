class ExchangeRateCommitmentAdjustmentJob < ApplicationJob
  queue_as :serial

  def perform(id)
    Chewy.strategy(:sidekiq) do
      @exchange_rate = ExchangeRate.find(id)
      # E30 — Edge case: only manual rates adjust commitments (a daily feed must not create daily adjustments)
      return unless @exchange_rate.manual?

      count = 0
      # Find the commitment with folio_currency
      commitments = CapitalCommitment.joins(:fund).where(entity_id: @exchange_rate.entity_id)
                                     .where(folio_currency: @exchange_rate.from).where("funds.currency=?", @exchange_rate.to)
      # E72 — Edge case: a fund's own rate adjusts only that fund's commitments
      commitments = commitments.where(fund_id: @exchange_rate.owner_id) if @exchange_rate.owner_type == "Fund"
      commitments.find_each do |cc|
        next unless cc.fund.currency == @exchange_rate.to
        # An entity-wide rate does not adjust a fund that uses its own rate for this pair and date
        next if @exchange_rate.owner_type.nil? && own_rate_takes_precedence?(cc.fund)

        cc.reload

        Rails.logger.debug { "Updating commitment due to exchange_rate for #{cc.investor_name} in #{cc.fund.name}" }

        amount_cents = cc.changed_committed_amount_at_exchange_rate(@exchange_rate.as_of)

        if amount_cents.zero?
          Rails.logger.debug { "No adjustment required for #{cc} for #{@exchange_rate}" }
        else
          reason = "Exchange Rate Changed: #{@exchange_rate}"
          as_of = @exchange_rate.as_of

          ca = CommitmentAdjustment.new(entity_id: cc.entity_id, fund_id: cc.fund_id, owner: @exchange_rate,
                                        capital_commitment: cc, amount_cents:, reason:, as_of:, adjustment_type: "Exchange Rate")

          AdjustmentCreate.call(commitment_adjustment: ca)
          Rails.logger.debug ca
        end

        count += 1
      end

      Rails.logger.debug { "Updated #{count} commitments due to exchange_rate change" }
    end
    nil
  end

  private

  # The fund's own rate wins on the same date, and FxRateResolver also picks a newer own rate over
  # an older entity-wide one — so any own rate on or after this rate's date takes precedence.
  def own_rate_takes_precedence?(fund)
    fund.features.use_own_fx_rates? &&
      ExchangeRate.exists?(entity_id: fund.entity_id, owner_type: "Fund", owner_id: fund.id,
                           from: @exchange_rate.from, to: @exchange_rate.to, as_of: @exchange_rate.as_of..)
  end
end
