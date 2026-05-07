class TrackingCurrencyJob < ApplicationJob
  queue_as :low

  # @param force [Boolean] If true, recalculates tracking amounts even if they are already present.
  #   Useful for retroactive corrections if historical exchange rates are updated.
  def perform(fund_id: nil, user_id: nil, entity_id: nil, force: false)
    Chewy.strategy(:sidekiq) do
      @error_msg = {}
      @missing_rates = Set.new # Tracks unique missing rate definitions for the final report

      funds = if fund_id.present?
                Fund.where(id: fund_id)
              elsif entity_id.present?
                Fund.where(entity_id: entity_id)
              else
                # Only funds belonging to entities with tracking currency enabled.
                # entity_currency_fmv_cents is populated for all such funds (regardless of whether
                # fund.currency matches entity.currency) so cross-fund SUM queries always work.
                Fund.joins(:entity).merge(Entity.where_permissions(:enable_tracking_currency))
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
      end

      # PI entity currency columns run for every fund so cross-fund SUM queries always work.
      @error_msg.merge!(convert_portfolio_investments(fund, force: force))

      send_notification("Tracking/entity currency updated for fund #{fund.name}", user_id)
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
      scope.where(payment_date: date)
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
      scope.where(remittance_date: date).find_each do |cr|
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
      scope.where(payment_date: date).update_all(
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
      scope.where(as_of: date)
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
    # Guard on the orig field — it is the only one converted at a point-in-time rate.
    # tracking_committed_amount_cents is always recomputed at the end of this method.
    scope = scope.where(tracking_orig_committed_amount_cents: 0) unless force

    # Each commitment's original pledge is converted at its own commitment_date rate.
    # Adjustments are handled separately in convert_commitment_adjustments (each at their as_of rate).
    scope.pluck(:commitment_date).compact.uniq.each do |date|
      rate = fund.tracking_exchange_rate(exchange_rate_date: date).rate
      scope.where(commitment_date: date).update_all(
        "tracking_orig_committed_amount_cents = orig_committed_amount_cents * #{rate}"
      )
    rescue StandardError
      @missing_rates << "Capital Commitments: #{fund.currency}->#{fund.tracking_currency} on #{date}"
    end

    # Rebuild tracking_adjustment_amount_cents from commitment_adjustments.tracking_amount_cents.
    # update_all in convert_commitment_adjustments bypasses counter_culture callbacks, so we fix counts here.
    CommitmentAdjustment.counter_culture_fix_counts(where: { fund_id: fund.id })

    # tracking_committed_amount_cents is derived from its two tracking components.
    # Recompute for all commitments so the total stays consistent with orig + adjustments.
    fund.capital_commitments.update_all(
      "tracking_committed_amount_cents = tracking_orig_committed_amount_cents + tracking_adjustment_amount_cents"
    )

    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    { "#{fund.name}: Capital Commitments" => e.message }
  end

  def convert_portfolio_investments(fund, force: false)
    send_notification("Updating entity/tracking currency for portfolio investments", nil)
    entity_currency = fund.entity.currency

    fund.portfolio_investments.find_each do |pi|
      updates = {}

      # --- Tracking currency amount (only when fund has a distinct tracking currency) ---
      if fund.has_tracking_currency? && (force || pi.tracking_amount_cents.zero?)
        rate = fund.tracking_exchange_rate(exchange_rate_date: pi.investment_date).rate
        updates[:tracking_amount_cents] = pi.amount_cents * rate
      end

      # --- Entity currency amount ---
      # Always written so cross-fund SUM queries work on a single column.
      # When currencies match, rate is 1 (direct copy of amount_cents).
      if force || pi.entity_currency_amount_cents.zero?
        entity_rate = entity_rate_for(fund, entity_currency, pi.investment_date)
        updates[:entity_currency_amount_cents] = pi.amount_cents * entity_rate if entity_rate
      end

      # --- FMV: always refresh to pick up new valuations or corrected exchange rates ---
      pi.compute_fmv
      updates[:fmv_cents] = pi.fmv_cents

      latest_valuation = pi.latest_valuation_on(Time.zone.today)
      if latest_valuation
        valuation_date = latest_valuation.valuation_date

        if fund.has_tracking_currency?
          fmv_rate = fund.tracking_exchange_rate(exchange_rate_date: valuation_date).rate
          updates[:tracking_fmv_cents] = pi.fmv_cents * fmv_rate
        end

        entity_fmv_rate = entity_rate_for(fund, entity_currency, valuation_date)
        updates[:entity_currency_fmv_cents] = pi.fmv_cents * entity_fmv_rate if entity_fmv_rate
      else
        updates[:entity_currency_fmv_cents] = 0
      end

      pi.update_columns(updates) if updates.any?
    rescue StandardError => e
      @missing_rates << "Portfolio Investment (#{pi.id}): #{e.message}"
      Rails.logger.error "Error updating PI #{pi.id}: #{e.message}"
    end

    PortfolioInvestment.counter_culture_fix_counts(where: { fund_id: fund.id })

    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    { "#{fund.name}: Portfolio Investments" => e.message }
  end

  # Returns the exchange rate multiplier from fund currency to the target currency.
  # Returns 1 when currencies are the same to avoid a DB lookup.
  def entity_rate_for(fund, target_currency, date)
    return 1 if fund.currency == target_currency

    er = fund.get_exchange_rate(fund.currency, target_currency, date)
    unless er
      @missing_rates << "Portfolio Investments: #{fund.currency}->#{target_currency} on #{date}"
      return nil
    end
    er.rate
  end
  # rubocop:enable Rails/SkipsModelValidations
end
