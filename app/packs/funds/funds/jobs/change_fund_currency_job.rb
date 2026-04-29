class ChangeFundCurrencyJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: 0

  def perform(fund_id, new_currency, user_id)
    fund = Fund.find(fund_id)
    old_currency = fund.currency

    return if old_currency == new_currency

    Audited.audit_class.as_user("ChangeFundCurrencyJob") do
      Chewy.strategy(:sidekiq) do
        @missing_rates = []
        @entity_id = fund.entity_id

        validate_pi_exchange_rates(fund, new_currency)
        validate_cashflow_exchange_rates(fund, old_currency, new_currency)

        if @missing_rates.any?
          send_notification(
            "#{fund.name}: currency change aborted — missing exchange rates: #{@missing_rates.join(', ')}",
            user_id, "danger"
          )
          return
        end

        send_notification("#{fund.name}: changing currency from #{old_currency} to #{new_currency}", user_id)

        # Step 2: Change fund currency — must happen before reprocessing so all
        # runtime reads of fund.currency see the new value
        fund.update_column(:currency, new_currency)
        fund.reload

        # Step 3: Recompute all fund-currency fields on each PI (amount, fmv, gains, etc.)
        reprocess_portfolio_investments(fund, user_id)

        # Step 4: Reconcile API counter-culture rollups accumulated from PI saves
        PortfolioInvestment.counter_culture_fix_counts(where: { fund_id: fund.id })

        # Step 5: Re-save each API to recompute avg_cost_cents (before_save callback)
        reprocess_aggregate_portfolio_investments(fund, user_id)

        # Step 6: Recompute attribution amounts (cost_of_sold, gain, sale_amount)
        # which are derived from PI price_per_share_cents (now in new currency)
        reprocess_portfolio_attributions(fund, user_id)

        # Step 7: Reconcile cost_of_sold_cents rollups on PI and API driven by attributions
        PortfolioAttribution.counter_culture_fix_counts(where: { fund_id: fund.id })

        # Step 8: Convert cashflow amounts from old to new currency using per-date exchange rates
        reprocess_portfolio_cashflows(fund, old_currency, new_currency, user_id)

        # Reconcile portfolio_income_cents on API driven by cashflows
        PortfolioCashflow.counter_culture_fix_counts(where: { fund_id: fund.id })

        # Step 9: Rebuild tracking currency amounts if the fund uses one
        if fund.has_tracking_currency?
          send_notification("#{fund.name}: updating tracking currency amounts", user_id)
          TrackingCurrencyJob.new.update_fund(fund, user_id, force: true)
        end

        # Step 10: Recompute fund ratios for every previously-computed end date
        recompute_fund_ratios(fund, user_id)

        log_final_stats(fund, old_currency, new_currency)

        send_notification(
          "#{fund.name}: currency change to #{new_currency} complete. Please refresh.",
          user_id
        )
      end
    end
  end

  private

  # rubocop:disable Rails/SkipsModelValidations

  def validate_pi_exchange_rates(fund, new_currency)
    fund.portfolio_investments
        .include_proforma
        .joins(:investment_instrument)
        .where.not(investment_instruments: { currency: new_currency })
        .pluck("investment_instruments.currency", :investment_date)
        .uniq
        .each do |instr_currency, date|
          next if instr_currency.blank?

          er = ExchangeRate.where(entity_id: @entity_id, from: instr_currency, to: new_currency)
                           .where(as_of: ..date).last
          @missing_rates << "PI: #{instr_currency}→#{new_currency} on #{date}" unless er
        end
  end

  def validate_cashflow_exchange_rates(fund, old_currency, new_currency)
    fund.portfolio_cashflows.pluck(:payment_date).compact.uniq.each do |date|
      er = ExchangeRate.where(entity_id: @entity_id, from: old_currency, to: new_currency)
                       .where(as_of: ..date).last
      @missing_rates << "Cashflow: #{old_currency}→#{new_currency} on #{date}" unless er
    end
  end

  def reprocess_portfolio_investments(fund, user_id)
    scope = fund.portfolio_investments.include_proforma
    send_notification("#{fund.name}: reprocessing #{scope.count} portfolio investments (incl. proforma)", user_id)
    scope.find_each do |pi|
      result = PortfolioInvestmentUpdate.call(portfolio_investment: pi)
      Rails.logger.error "Failed to update PI #{pi.id}: #{result[:errors]}" unless result.success?
    end
  end

  def reprocess_aggregate_portfolio_investments(fund, user_id)
    send_notification("#{fund.name}: recomputing aggregate portfolio investment metrics", user_id)
    fund.aggregate_portfolio_investments.find_each(&:save)
  end

  def reprocess_portfolio_attributions(fund, user_id)
    send_notification("#{fund.name}: reprocessing #{fund.portfolio_attributions.count} portfolio attributions", user_id)
    fund.portfolio_attributions.find_each do |pa|
      pa.compute_amounts
      pa.save
    end
  end

  def reprocess_portfolio_cashflows(fund, old_currency, new_currency, user_id)
    send_notification(
      "#{fund.name}: converting portfolio cashflows from #{old_currency} to #{new_currency}",
      user_id
    )
    fund.portfolio_cashflows.pluck(:payment_date).compact.uniq.each do |date|
      er = ExchangeRate.where(entity_id: fund.entity_id, from: old_currency, to: new_currency)
                       .where(as_of: ..date).last
      next unless er

      fund.portfolio_cashflows.where(payment_date: date)
          .update_all("amount_cents = amount_cents * #{er.rate}")
    end
  end

  def log_final_stats(fund, old_currency, new_currency)
    pi_scope   = fund.portfolio_investments.include_proforma
    ratio_dates = fund.fund_ratios.pluck(:end_date).uniq

    Rails.logger.info do
      <<~MSG.squish
        [ChangeFundCurrencyJob] #{fund.name} (id=#{fund.id})
        currency: #{old_currency} → #{new_currency} |
        portfolio_investments: #{pi_scope.where(proforma: false).count} regular + #{pi_scope.where(proforma: true).count} proforma |
        aggregate_portfolio_investments: #{fund.aggregate_portfolio_investments.count} |
        portfolio_attributions: #{fund.portfolio_attributions.count} |
        portfolio_cashflows: #{fund.portfolio_cashflows.count} |
        fund_ratio end_dates requeued: #{ratio_dates.size} (#{ratio_dates.min}..#{ratio_dates.max}) |
        tracking_currency: #{fund.tracking_currency.presence || 'none'}
      MSG
    end
  end

  def recompute_fund_ratios(fund, user_id)
    end_dates = fund.fund_ratios.pluck(:end_date).uniq
    return if end_dates.empty?

    send_notification("#{fund.name}: recomputing fund ratios for #{end_dates.size} date(s)", user_id)
    end_dates.each do |end_date|
      FundRatiosJob.perform_later(fund.id, nil, end_date, user_id, true)
    end
  end

  # rubocop:enable Rails/SkipsModelValidations
end
