class TrackingCurrencyJob < ApplicationJob
  queue_as :low

  def perform(fund_id: nil, user_id: nil)
    Chewy.strategy(:sidekiq) do
      @error_msg = {}

      funds = if fund_id.nil?
                # This is run daily, to compute for all funds that have tracking currency
                Fund.where("tracking_currency <> currency")
              else
                # This is run when a specific fund needs to be updated
                Fund.where(id: fund_id)
              end

      funds.each do |fund|
        update_fund(fund, user_id)
      rescue StandardError => e
        Rails.logger.debug e.backtrace
        send_notification("Error updating tracking currency for fund #{fund.name}: #{e.message}", user_id, :danger)
        @error_msg[:from] = "TrackingCurrencyJob"
        @error_msg[fund.name] = e.message
      end

      EntityMailer.with(error_msg: @error_msg).notify_errors.deliver_now if @error_msg.present?
    end
  end

  # rubocop:disable Metrics/BlockLength
  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Rails/SkipsModelValidations
  def update_fund(fund, user_id)
    Audited.audit_class.as_user("TrackingCurrencyJob") do
      if fund.has_tracking_currency?
        # Convert account entry
        send_notification("Updating tracking currency for account entries", user_id)
        fund.account_entries.where(tracking_amount_cents: 0).find_each do |ae|
          ae.tracking_amount_cents = ae.amount_cents * ae.tracking_exchange_rate.rate
          ae.save
        end

        # Convert remittance payments
        send_notification("Updating tracking currency for remittance payments", user_id)
        fund.capital_remittance_payments.where(tracking_amount_cents: 0).find_each do |crp|
          crp.tracking_amount_cents = crp.amount_cents * crp.tracking_exchange_rate.rate
          crp.save
        end

        # Convert remittances
        send_notification("Updating tracking currency for remittances", user_id)
        fund.capital_remittances.where(tracking_call_amount_cents: 0).find_each do |cr|
          cr.tracking_call_amount_cents = cr.call_amount_cents * cr.tracking_exchange_rate.rate
          cr.save
        end

        # Convert distributions
        send_notification("Updating tracking currency for distribution payments", user_id)
        fund.capital_distribution_payments.where(tracking_net_payable_cents: 0).find_each do |cdp|
          cdp.tracking_net_payable_cents = cdp.net_payable_cents * cdp.tracking_exchange_rate.rate
          cdp.tracking_gross_payable_cents = cdp.gross_payable_cents * cdp.tracking_exchange_rate.rate
          cdp.tracking_reinvestment_with_fees_cents = cdp.reinvestment_with_fees_cents * cdp.tracking_exchange_rate.rate
          cdp.save
        end

        # Convert CommitmentAdjustment
        send_notification("Updating tracking currency for commitment adjustments", user_id)
        fund.commitment_adjustments.where(tracking_amount_cents: 0).find_each do |ca|
          ca.tracking_amount_cents = ca.amount_cents * ca.tracking_exchange_rate.rate
          ca.save
        end

        # Convert CapitalCommitment
        send_notification("Updating tracking currency for capital commitments", user_id)
        fund.capital_commitments.where(tracking_orig_committed_amount_cents: 0).find_each do |cc|
          # This is only those commitments whose tracking_orig_committed_amount_cents has not been converted
          cc.tracking_orig_committed_amount_cents = cc.orig_committed_amount_cents * cc.tracking_exchange_rate.rate
          cc.save
        end

        # This job runs early morning at 1 am, so find those commitments that were updated yesterday
        fund.capital_commitments.where(updated_at: (Time.zone.today - 1.day)..).find_each do |cc|
          tracking_committed_amount_cents = cc.tracking_orig_committed_amount_cents + cc.tracking_adjustment_amount_cents
          # Dont update the last updated_at
          cc.update_columns(tracking_committed_amount_cents:)
        end

        msg = "Tracking currency updated for fund #{fund.name}"
        send_notification(msg, user_id)
      else
        msg = "#{fund.name} tracking currency not present, skipping conversion to tracking currency"
        send_notification(msg, user_id, :info)
        Rails.logger.debug { msg }
      end
    end
  end
  # rubocop:enable Metrics/BlockLength
  # rubocop:enable Metrics/MethodLength
  # rubocop:enable Rails/SkipsModelValidations
end
