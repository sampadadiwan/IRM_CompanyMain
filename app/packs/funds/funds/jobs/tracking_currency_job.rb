class TrackingCurrencyJob < ApplicationJob
  queue_as :low

  # @param force [Boolean] If true, recalculates tracking amounts even if they are already present.
  #   Useful for retroactive corrections if historical exchange rates are updated.
  def perform(fund_id: nil, user_id: nil, entity_id: nil, force: false)
    Chewy.strategy(:sidekiq) do
      @error_msg = {}
      @missing_rates = Set.new # Tracks unique missing rate definitions for the final report

      funds = if fund_id.present?
                # This is run when a specific fund needs to be updated
                Fund.where(id: fund_id)
              elsif entity_id.present?
                # This is run when all funds for an entity need to be updated, typically called when an exchangee rate changes
                Fund.where(entity_id: entity_id)
              else
                # This is run daily, to compute for all funds that have tracking currency
                Fund.where("tracking_currency <> currency")
              end

      funds.each do |fund|
        update_fund(fund, user_id, force: force)
      rescue StandardError => e
        Rails.logger.debug e.backtrace
        send_notification("Error updating tracking currency for fund #{fund.name}: #{e.message}", user_id, :danger)
        @error_msg[:from] = "TrackingCurrencyJob"
        @error_msg[fund.name] = e.message
      end

      @error_msg[:missing_rates] = @missing_rates.to_a if @missing_rates.any?

      send_errors_notification("Errors occurred during Tracking Currency Job", @error_msg, user_id) if @error_msg.present?

      EntityMailer.with(error_msg: @error_msg, entity_id: entity_id).notify_errors.deliver_now if @error_msg.present?
    end
  end

  # rubocop:disable Rails/SkipsModelValidations
  def update_fund(fund, user_id, force: false)
    Audited.audit_class.as_user("TrackingCurrencyJob") do
      if fund.has_tracking_currency?
        @error_msg.merge!(convert_account_entries(fund, user_id, force: force))
        @error_msg.merge!(convert_remittance_payments(fund, user_id, force: force))
        @error_msg.merge!(convert_remittances(fund, user_id, force: force))
        @error_msg.merge!(convert_distributions(fund, user_id, force: force))
        @error_msg.merge!(convert_commitment_adjustments(fund, user_id, force: force))
        @error_msg.merge!(convert_capital_commitments(fund, user_id, force: force))
        @error_msg.merge!(convert_portfolio_investments(fund, force: force))

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

  def convert_account_entries(fund, user_id, force: false)
    send_notification("Updating tracking currency for account entries", user_id)
    scope = fund.account_entries
    # By default, we only process new entries (tracking_amount_cents == 0)
    scope = scope.where(tracking_amount_cents: 0) unless force

    # Batch process by reporting_date to minimize exchange rate lookups
    scope.pluck(:reporting_date).compact.uniq.each do |date|
      # Fetch the rate between Fund Base Currency and Tracking Currency for this specific date
      rate = fund.tracking_exchange_rate(exchange_rate_date: date).rate

      # Standard amounts are converted using the daily exchange rate
      scope.where(reporting_date: date)
           .where.not("name LIKE ?", "%Percentage%")
           .update_all("tracking_amount_cents = amount_cents * #{rate}")

      # Exception: Entries representing a 'Percentage' (e.g., Ownership %) are not currency-dependent
      # and should maintain a 1:1 ratio with the base amount.
      scope.where(reporting_date: date)
           .where("name LIKE ?", "%Percentage%")
           .update_all("tracking_amount_cents = amount_cents")
    rescue StandardError => e
      @missing_rates << "Account Entries: #{fund.currency}->#{fund.tracking_currency} on #{date}"
      Rails.logger.error "Error updating tracking currency for account entries on #{date}: #{e.message}"
    end
    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    { "#{fund.name}: Account Entries" => e.message }
  end

  def convert_remittance_payments(fund, user_id, force: false)
    send_notification("Updating tracking currency for remittance payments", user_id)
    scope = fund.capital_remittance_payments
    scope = scope.where(tracking_amount_cents: 0) unless force

    # Conversion is based on the date the payment was actually received
    scope.pluck(:payment_date).compact.uniq.each do |date|
      rate = fund.tracking_exchange_rate(exchange_rate_date: date).rate
      fund.capital_remittance_payments.where(payment_date: date)
          .update_all("tracking_amount_cents = amount_cents * #{rate}")
    rescue StandardError
      @missing_rates << "Remittance Payments: #{fund.currency}->#{fund.tracking_currency} on #{date}"
    end

    # Ensure counter caches (totals) on the parent Remittance are updated after payment changes
    fund.capital_remittance_payments.counter_culture_fix_counts
    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    { "#{fund.name}: Remittance Payments" => e.message }
  end

  def convert_remittances(fund, user_id, force: false)
    send_notification("Updating tracking currency for remittances", user_id)
    # We convert both verified and unverified remittances to provide a complete tracking view
    scope = fund.capital_remittances
    scope = scope.where(tracking_call_amount_cents: 0) unless force

    # Remittance conversion is based on the original call date
    scope.pluck(:remittance_date).compact.uniq.each do |date|
      rate = fund.tracking_exchange_rate(exchange_rate_date: date).rate
      fund.capital_remittances.where(remittance_date: date).find_each do |cr|
        # tracking_collected_amount is a rollup of the tracking amounts of individual payments
        cr.update_columns(
          tracking_call_amount_cents: cr.call_amount_cents * rate,
          tracking_collected_amount_cents: cr.capital_remittance_payments.sum(:tracking_amount_cents)
        )
      end
    rescue StandardError
      @missing_rates << "Remittances: #{fund.currency}->#{fund.tracking_currency} on #{date}"
    end
    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    { "#{fund.name}: Remittances" => e.message }
  end

  def convert_distributions(fund, user_id, force: false)
    send_notification("Updating tracking currency for distribution payments", user_id)
    scope = fund.capital_distribution_payments
    scope = scope.where(tracking_net_payable_cents: 0) unless force

    # Distribution payments are converted based on their specific payment date
    scope.pluck(:payment_date).compact.uniq.each do |date|
      rate = fund.tracking_exchange_rate(exchange_rate_date: date).rate
      fund.capital_distribution_payments.where(payment_date: date).update_all(
        "tracking_net_payable_cents = net_payable_cents * #{rate},
         tracking_gross_payable_cents = gross_payable_cents * #{rate},
         tracking_reinvestment_with_fees_cents = reinvestment_with_fees_cents * #{rate}"
      )
    rescue StandardError
      @missing_rates << "Distributions: #{fund.currency}->#{fund.tracking_currency} on #{date}"
    end
    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    { "#{fund.name}: Distributions" => e.message }
  end

  def convert_commitment_adjustments(fund, user_id, force: false)
    send_notification("Updating tracking currency for commitment adjustments", user_id)
    scope = fund.commitment_adjustments
    scope = scope.where(tracking_amount_cents: 0) unless force

    # Commitment adjustments use the 'as_of' date for currency conversion
    scope.pluck(:as_of).compact.uniq.each do |date|
      rate = fund.tracking_exchange_rate(exchange_rate_date: date).rate
      fund.commitment_adjustments.where(as_of: date)
          .update_all("tracking_amount_cents = amount_cents * #{rate}")
    rescue StandardError
      @missing_rates << "Commitment Adjustments: #{fund.currency}->#{fund.tracking_currency} on #{date}"
    end
    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    { "#{fund.name}: Commitment Adjustments" => e.message }
  end

  def convert_capital_commitments(fund, user_id, force: false)
    send_notification("Updating tracking currency for capital commitments", user_id)
    scope = fund.capital_commitments
    scope = scope.where(tracking_committed_amount_cents: 0) unless force

    # Capital commitments are converted based on the date the commitment was signed/effective
    scope.pluck(:commitment_date).compact.uniq.each do |date|
      rate = fund.tracking_exchange_rate(exchange_rate_date: date).rate
      fund.capital_commitments.where(commitment_date: date).update_all(
        # This is incorrect - TODO fix
        "tracking_committed_amount_cents = committed_amount_cents * #{rate},
         tracking_orig_committed_amount_cents = orig_committed_amount_cents * #{rate}"
      )
    rescue StandardError
      @missing_rates << "Capital Commitments: #{fund.currency}->#{fund.tracking_currency} on #{date}"
    end
    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    { "#{fund.name}: Capital Commitments" => e.message }
  end

  def convert_portfolio_investments(fund, force: false)
    send_notification("Updating tracking currency for portfolio investments", nil)
    # Always check FMV for all PIs, but only update investment amount if forced or not yet set
    fund.portfolio_investments.find_each do |pi|
      updates = {}

      # Update original investment amount to tracking currency
      if force || pi.tracking_amount_cents.zero?
        rate = fund.tracking_exchange_rate(exchange_rate_date: pi.investment_date).rate
        updates[:tracking_amount_cents] = pi.amount_cents * rate
      end

      # Dynamic FMV Refresh: Tracking FMV is refreshed every time to account for new valuations
      # or corrected historical exchange rates for valuation dates.
      latest_valuation = pi.latest_valuation_on(Time.zone.today)
      if latest_valuation
        fmv_rate = fund.tracking_exchange_rate(exchange_rate_date: latest_valuation.valuation_date).rate
        updates[:tracking_fmv_cents] = pi.fmv_cents * fmv_rate
      end

      pi.update_columns(updates) if updates.any?
    rescue StandardError => e
      @missing_rates << "Portfolio Investment (#{pi.id}): Missing rate for conversion"
      Rails.logger.error "Error updating PI #{pi.id}: #{e.message}"
    end

    # Recalculate counter culture totals for Portfolio Investments at the fund level
    PortfolioInvestment.counter_culture_fix_counts(where: { fund_id: fund.id })

    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    { "#{fund.name}: Portfolio Investments" => e.message }
  end
  # rubocop:enable Rails/SkipsModelValidations
end
