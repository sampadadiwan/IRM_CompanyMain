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

  # rubocop:disable Rails/SkipsModelValidations
  def update_fund(fund, user_id)
    Audited.audit_class.as_user("TrackingCurrencyJob") do
      if fund.has_tracking_currency?
        @error_msg.merge!(convert_account_entries(fund, user_id))
        @error_msg.merge!(convert_remittance_payments(fund, user_id))
        @error_msg.merge!(convert_remittances(fund, user_id))
        @error_msg.merge!(convert_distributions(fund, user_id))
        @error_msg.merge!(convert_commitment_adjustments(fund, user_id))
        @error_msg.merge!(convert_initial_capital_commitments(fund, user_id))
        @error_msg.merge!(update_capital_commitments_from_yesterday(fund))
        @error_msg.merge!(convert_portfolio_investments(fund))

        msg = "Tracking currency updated for fund #{fund.name}"
        send_notification(msg, user_id)
      else
        msg = "#{fund.name} tracking currency not present, skipping conversion to tracking currency"
        send_notification(msg, user_id, :info)
        Rails.logger.debug { msg }
      end
    end
  end

  private

  def convert_account_entries(fund, user_id)
    send_notification("Updating tracking currency for account entries", user_id)
    fund.account_entries.where(tracking_amount_cents: 0).find_each do |ae|
      ae.tracking_amount_cents = if ae.name.include?("Percentage")
                                   ae.amount_cents
                                 else
                                   ae.amount_cents * ae.tracking_exchange_rate.rate
                                 end
      ae.save
    end
    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    send_notification("Error updating tracking currency for account entries for fund #{fund.name}: #{e.message}", user_id, :danger)
    { "Account Entries" => e.message }
  end

  def convert_remittance_payments(fund, user_id)
    send_notification("Updating tracking currency for remittance payments", user_id)
    fund.capital_remittance_payments.where(tracking_amount_cents: 0).find_each do |crp|
      # We dont save, but only use update_columns, to avoid the capital_remittance getting unverified
      # When a payment changes it auto unverifies the remittance, we need to avoid this.
      tracking_amount_cents = crp.amount_cents * crp.tracking_exchange_rate.rate
      crp.update_columns(tracking_amount_cents: tracking_amount_cents)
    end
    # Rollup the remittance payments
    fund.capital_remittance_payments.counter_culture_fix_counts
    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    send_notification("Error updating tracking currency for remittance payments for fund #{fund.name}: #{e.message}", user_id, :danger)
    { "Remittance Payments" => e.message }
  end

  def convert_remittances(fund, user_id)
    send_notification("Updating tracking currency for remittances", user_id)
    fund.capital_remittances.where(tracking_call_amount_cents: 0).find_each do |cr|
      cr.tracking_call_amount_cents = cr.call_amount_cents * cr.tracking_exchange_rate.rate
      cr.save
    end
    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    send_notification("Error updating tracking currency for remittances for fund #{fund.name}: #{e.message}", user_id, :danger)
    { "Remittances" => e.message }
  end

  def convert_distributions(fund, user_id)
    send_notification("Updating tracking currency for distribution payments", user_id)
    fund.capital_distribution_payments.where(tracking_net_payable_cents: 0).find_each do |cdp|
      cdp.tracking_net_payable_cents = cdp.net_payable_cents * cdp.tracking_exchange_rate.rate
      cdp.tracking_gross_payable_cents = cdp.gross_payable_cents * cdp.tracking_exchange_rate.rate
      cdp.tracking_reinvestment_with_fees_cents = cdp.reinvestment_with_fees_cents * cdp.tracking_exchange_rate.rate
      cdp.save
    end
    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    send_notification("Error updating tracking currency for distribution payments for fund #{fund.name}: #{e.message}", user_id, :danger)
    { "Distributions" => e.message }
  end

  def convert_commitment_adjustments(fund, user_id)
    send_notification("Updating tracking currency for commitment adjustments", user_id)
    fund.commitment_adjustments.where(tracking_amount_cents: 0).find_each do |ca|
      ca.tracking_amount_cents = ca.amount_cents * ca.tracking_exchange_rate.rate
      ca.save
    end
    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    send_notification("Error updating tracking currency for commitment adjustments for fund #{fund.name}: #{e.message}", user_id, :danger)
    { "Commitment Adjustments" => e.message }
  end

  def convert_initial_capital_commitments(fund, user_id)
    send_notification("Updating tracking currency for capital commitments", user_id)
    fund.capital_commitments.where(tracking_orig_committed_amount_cents: 0).find_each do |cc|
      # This is only those commitments whose tracking_orig_committed_amount_cents has not been converted
      cc.tracking_orig_committed_amount_cents = cc.orig_committed_amount_cents * cc.tracking_exchange_rate.rate
      cc.save
    end
    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    send_notification("Error updating tracking currency for capital commitments for fund #{fund.name}: #{e.message}", user_id, :danger)
    { "Initial Capital Commitments" => e.message }
  end

  def update_capital_commitments_from_yesterday(fund)
    fund.capital_commitments.where(updated_at: (Time.zone.today - 1.day)..).find_each do |cc|
      tracking_committed_amount_cents = cc.tracking_orig_committed_amount_cents + cc.tracking_adjustment_amount_cents
      # Dont update the last updated_at
      cc.update_columns(tracking_committed_amount_cents:)
    end
    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    send_notification("Error updating capital commitments from yesterday for fund #{fund.name}: #{e.message}", nil, :danger) # user_id is not available here
    { "Updated Capital Commitments" => e.message }
  end

  def convert_portfolio_investments(fund)
    fund.portfolio_investments.each do |pi|
      tracking_amount_cents = pi.amount_cents * pi.tracking_exchange_rate(exchange_rate_date: pi.investment_date).rate
      latest_valuation = pi.latest_valuation_on(Time.zone.today)
      tracking_fmv_cents = pi.fmv_cents * pi.tracking_exchange_rate(exchange_rate_date: latest_valuation.valuation_date).rate
      pi.update_columns(tracking_amount_cents:, tracking_fmv_cents:)
    end
    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    send_notification("Error updating tracking currency for portfolio investments for fund #{fund.name}: #{e.message}", nil, :danger) # user_id is not available here
    { "Portfolio Investments" => e.message }
  end
  # rubocop:enable Rails/SkipsModelValidations
end
