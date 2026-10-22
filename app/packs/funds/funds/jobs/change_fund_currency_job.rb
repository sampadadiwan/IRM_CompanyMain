class ChangeFundCurrencyJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: 0

  def perform(fund_id, new_currency, user_id)
    fund = Fund.find(fund_id)
    old_currency = fund.currency

    return if old_currency == new_currency

    unless fund.entity.entity_setting&.sandbox
      send_notification(
        "#{fund.name}: currency change aborted — entity must be in sandbox mode",
        user_id, "danger"
      )
      return
    end

    Audited.audit_class.as_user("ChangeFundCurrencyJob") do
      Chewy.strategy(:sidekiq) do
        @missing_rates = []
        @entity_id = fund.entity_id

        # Portfolio side
        validate_pi_exchange_rates(fund, new_currency)
        validate_cashflow_exchange_rates(fund, old_currency, new_currency)

        # Capital/commitment side
        validate_account_entry_exchange_rates(fund, old_currency, new_currency)
        validate_commitment_adjustment_exchange_rates(fund, old_currency, new_currency)
        validate_fund_unit_exchange_rates(fund, old_currency, new_currency)
        validate_remittance_payment_exchange_rates(fund, new_currency)
        validate_remittance_exchange_rates(fund, old_currency, new_currency)
        validate_distribution_payment_exchange_rates(fund, old_currency, new_currency)
        validate_distribution_header_exchange_rates(fund, old_currency, new_currency)
        validate_commitment_exchange_rates(fund, new_currency)

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

        # Step 9: Convert account entry amounts (fund-currency only; folio and tracking untouched)
        reprocess_account_entries(fund, old_currency, new_currency, user_id)

        # Step 10: Convert commitment adjustment amounts; fix rollups to CapitalCommitment
        reprocess_commitment_adjustments(fund, old_currency, new_currency, user_id)

        # Step 11: Convert fund unit prices; recompute derived amounts; fix rollups to CapitalCommitment/Fund
        reprocess_fund_units(fund, old_currency, new_currency, user_id)

        # Step 12: Re-derive remittance payment amounts from folio; fix rollups to CapitalRemittance
        reprocess_remittance_payments(fund, new_currency, user_id)

        # Step 13: Convert remittance call/fee amounts; fix rollups to CapitalCall and CapitalCommitment
        reprocess_remittances(fund, old_currency, new_currency, user_id)

        # Step 14: Convert distribution payment amounts; fix rollups to CapitalDistribution and CapitalCommitment
        reprocess_distribution_payments(fund, old_currency, new_currency, user_id)

        # Step 15: Convert capital distribution non-rollup header amounts
        reprocess_capital_distributions(fund, old_currency, new_currency, user_id)

        # Step 16: Re-derive capital commitment amounts from folio; recompute committed total
        reprocess_capital_commitments(fund, new_currency, user_id)

        # Step 17: Convert capital call amount_to_be_called_cents (all other amounts are rollups fixed above)
        reprocess_capital_calls(fund, old_currency, new_currency, user_id)

        # Step 18: Rebuild tracking currency amounts if the fund uses one
        if fund.has_tracking_currency?
          send_notification("#{fund.name}: updating tracking currency amounts", user_id)
          # rebuild_fund, not update_fund: update_fund needs the error state only #perform sets up.
          tracking_errors = TrackingCurrencyJob.new.rebuild_fund(fund, user_id)
          if tracking_errors.present?
            send_notification("#{fund.name}: some tracking amounts could not be rebuilt: #{tracking_errors.to_json}",
                              user_id, "danger")
          end
        end

        # Step 19: Recompute fund ratios for every previously-computed end date
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

  # ── Validation helpers ────────────────────────────────────────────────────

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

  def validate_account_entry_exchange_rates(fund, old_currency, new_currency)
    # distinct.pluck dedups in SQL — plain pluck built a Ruby array with one Date per
    # ledger row (millions for a large fund) just to uniq it down to a handful of dates
    fund.account_entries.distinct.pluck(:reporting_date).compact.each do |date|
      er = ExchangeRate.where(entity_id: @entity_id, from: old_currency, to: new_currency)
                       .where(as_of: ..date).last
      @missing_rates << "AccountEntry: #{old_currency}→#{new_currency} on #{date}" unless er
    end
  end

  def validate_commitment_adjustment_exchange_rates(fund, old_currency, new_currency)
    fund.commitment_adjustments.pluck(:as_of).compact.uniq.each do |date|
      er = ExchangeRate.where(entity_id: @entity_id, from: old_currency, to: new_currency)
                       .where(as_of: ..date).last
      @missing_rates << "CommitmentAdjustment: #{old_currency}→#{new_currency} on #{date}" unless er
    end
  end

  def validate_fund_unit_exchange_rates(fund, old_currency, new_currency)
    fund.fund_units.pluck(:issue_date).compact.uniq.each do |date|
      er = ExchangeRate.where(entity_id: @entity_id, from: old_currency, to: new_currency)
                       .where(as_of: ..date).last
      @missing_rates << "FundUnit: #{old_currency}→#{new_currency} on #{date}" unless er
    end
  end

  def validate_remittance_payment_exchange_rates(fund, new_currency)
    fund.capital_remittance_payments
        .joins(capital_remittance: :capital_commitment)
        .pluck("capital_commitments.folio_currency", "capital_remittance_payments.payment_date")
        .uniq
        .each do |folio_currency, date|
          next if folio_currency.blank? || date.nil? || folio_currency == new_currency

          er = ExchangeRate.where(entity_id: @entity_id, from: folio_currency, to: new_currency)
                           .where(as_of: ..date).last
          @missing_rates << "RemittancePayment: #{folio_currency}→#{new_currency} on #{date}" unless er
        end
  end

  def validate_remittance_exchange_rates(fund, old_currency, new_currency)
    fund.capital_remittances.pluck(:remittance_date).compact.uniq.each do |date|
      er = ExchangeRate.where(entity_id: @entity_id, from: old_currency, to: new_currency)
                       .where(as_of: ..date).last
      @missing_rates << "Remittance: #{old_currency}→#{new_currency} on #{date}" unless er
    end
  end

  def validate_distribution_payment_exchange_rates(fund, old_currency, new_currency)
    fund.capital_distribution_payments.pluck(:payment_date).compact.uniq.each do |date|
      er = ExchangeRate.where(entity_id: @entity_id, from: old_currency, to: new_currency)
                       .where(as_of: ..date).last
      @missing_rates << "DistributionPayment: #{old_currency}→#{new_currency} on #{date}" unless er
    end
  end

  def validate_distribution_header_exchange_rates(fund, old_currency, new_currency)
    fund.capital_distributions.pluck(:distribution_date).compact.uniq.each do |date|
      er = ExchangeRate.where(entity_id: @entity_id, from: old_currency, to: new_currency)
                       .where(as_of: ..date).last
      @missing_rates << "CapitalDistribution: #{old_currency}→#{new_currency} on #{date}" unless er
    end
  end

  def validate_commitment_exchange_rates(fund, new_currency)
    fund.capital_commitments
        .pluck(:folio_currency, :commitment_date)
        .uniq
        .each do |folio_currency, date|
          next if folio_currency.blank? || date.nil? || folio_currency == new_currency

          er = ExchangeRate.where(entity_id: @entity_id, from: folio_currency, to: new_currency)
                           .where(as_of: ..date).last
          @missing_rates << "Commitment: #{folio_currency}→#{new_currency} on #{date}" unless er
        end
  end

  # ── Portfolio pipeline ────────────────────────────────────────────────────

  def reprocess_portfolio_investments(fund, user_id)
    scope = fund.portfolio_investments.include_proforma
    send_notification("#{fund.name}: reprocessing #{scope.count} portfolio investments (incl. proforma)", user_id)
    # Each batch's sold/transferred quantities in two grouped queries, not two SUMs per investment
    PortfolioInvestment.find_each_with_buy_quantities(scope) do |pi|
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

  # ── Capital/commitment pipeline ───────────────────────────────────────────

  def reprocess_account_entries(fund, old_currency, new_currency, user_id)
    send_notification("#{fund.name}: converting #{fund.account_entries.count} account entries", user_id)
    # distinct.pluck dedups in SQL instead of materializing one Date per ledger row
    fund.account_entries.distinct.pluck(:reporting_date).compact.each do |date|
      er = ExchangeRate.where(entity_id: fund.entity_id, from: old_currency, to: new_currency)
                       .where(as_of: ..date).last
      next unless er

      fund.account_entries.where(reporting_date: date)
          .update_all("amount_cents = amount_cents * #{er.rate}")
    end
  end

  def reprocess_commitment_adjustments(fund, old_currency, new_currency, user_id)
    send_notification("#{fund.name}: converting #{fund.commitment_adjustments.count} commitment adjustments", user_id)
    fund.commitment_adjustments.pluck(:as_of).compact.uniq.each do |date|
      er = ExchangeRate.where(entity_id: fund.entity_id, from: old_currency, to: new_currency)
                       .where(as_of: ..date).last
      next unless er

      fund.commitment_adjustments.where(as_of: date).update_all(
        "amount_cents          = amount_cents          * #{er.rate},
         pre_adjustment_cents  = pre_adjustment_cents  * #{er.rate},
         post_adjustment_cents = post_adjustment_cents * #{er.rate}"
      )
    end
    # Propagates adjustment_amount_cents to CapitalCommitment
    CommitmentAdjustment.counter_culture_fix_counts(where: { fund_id: fund.id })
  end

  def reprocess_fund_units(fund, old_currency, new_currency, user_id)
    send_notification("#{fund.name}: converting #{fund.fund_units.count} fund units", user_id)
    fund.fund_units.pluck(:issue_date).compact.uniq.each do |date|
      er = ExchangeRate.where(entity_id: fund.entity_id, from: old_currency, to: new_currency)
                       .where(as_of: ..date).last
      next unless er

      # Convert the stored price components first, then recompute derived fields
      # in a second pass so RHS reads the already-converted values
      fund.fund_units.where(issue_date: date).update_all(
        "price_cents   = price_cents   * #{er.rate},
         premium_cents = premium_cents * #{er.rate}"
      )
      fund.fund_units.where(issue_date: date).update_all(
        "amount_cents        = quantity * (price_cents + premium_cents),
         total_premium_cents = quantity * premium_cents"
      )
    end
    # Propagates total_units_amount_cents / total_units_premium_cents to CapitalCommitment and Fund
    FundUnit.counter_culture_fix_counts(where: { fund_id: fund.id })
  end

  def reprocess_remittance_payments(fund, new_currency, user_id)
    send_notification(
      "#{fund.name}: re-deriving #{fund.capital_remittance_payments.count} remittance payment amounts from folio",
      user_id
    )
    fund.capital_remittance_payments
        .joins(capital_remittance: :capital_commitment)
        .pluck("capital_commitments.folio_currency", "capital_remittance_payments.payment_date")
        .uniq
        .each do |folio_currency, date|
          next if folio_currency.blank? || date.nil?

          scope = fund.capital_remittance_payments
                      .joins(capital_remittance: :capital_commitment)
                      .where(capital_commitments: { folio_currency: folio_currency }, payment_date: date)

          if folio_currency == new_currency
            # No rate lookup needed — folio and fund currency are now the same
            scope.update_all("capital_remittance_payments.amount_cents = capital_remittance_payments.folio_amount_cents")
          else
            er = ExchangeRate.where(entity_id: fund.entity_id, from: folio_currency, to: new_currency)
                             .where(as_of: ..date).last
            next unless er

            scope.update_all("capital_remittance_payments.amount_cents = capital_remittance_payments.folio_amount_cents * #{er.rate}")
          end
        end
    # Propagates collected_amount_cents to CapitalRemittance
    CapitalRemittancePayment.counter_culture_fix_counts(where: { fund_id: fund.id })
  end

  def reprocess_remittances(fund, old_currency, new_currency, user_id)
    send_notification("#{fund.name}: converting #{fund.capital_remittances.count} remittance amounts", user_id)
    fund.capital_remittances.pluck(:remittance_date).compact.uniq.each do |date|
      er = ExchangeRate.where(entity_id: fund.entity_id, from: old_currency, to: new_currency)
                       .where(as_of: ..date).last
      next unless er

      # collected_amount_cents and arrear_amount_cents are rollups — handled by fix_counts below
      fund.capital_remittances.where(remittance_date: date).update_all(
        "call_amount_cents       = call_amount_cents       * #{er.rate},
         investment_amount_cents = investment_amount_cents * #{er.rate},
         capital_fee_cents       = capital_fee_cents       * #{er.rate},
         other_fee_cents         = other_fee_cents         * #{er.rate},
         computed_amount_cents   = computed_amount_cents   * #{er.rate},
         committed_amount_cents  = committed_amount_cents  * #{er.rate}"
      )
    end
    # Propagates call_amount_cents, capital_fee_cents, other_fee_cents, collected_amount_cents
    # to CapitalCall and CapitalCommitment
    CapitalRemittance.counter_culture_fix_counts(where: { fund_id: fund.id })
  end

  def reprocess_distribution_payments(fund, old_currency, new_currency, user_id)
    send_notification(
      "#{fund.name}: converting #{fund.capital_distribution_payments.count} distribution payment amounts",
      user_id
    )
    fund.capital_distribution_payments.pluck(:payment_date).compact.uniq.each do |date|
      er = ExchangeRate.where(entity_id: fund.entity_id, from: old_currency, to: new_currency)
                       .where(as_of: ..date).last
      next unless er

      # folio_amount_cents is in folio currency — untouched
      # tracking_net_payable_cents is rebuilt by TrackingCurrencyJob
      # net_of_account_entries_cents participates in fund-currency arithmetic despite its monetize declaration
      fund.capital_distribution_payments.where(payment_date: date).update_all(
        "income_cents                       = income_cents                       * #{er.rate},
         income_with_fees_cents             = income_with_fees_cents             * #{er.rate},
         cost_of_investment_cents           = cost_of_investment_cents           * #{er.rate},
         cost_of_investment_with_fees_cents = cost_of_investment_with_fees_cents * #{er.rate},
         net_payable_cents                  = net_payable_cents                  * #{er.rate},
         gross_payable_cents                = gross_payable_cents                * #{er.rate},
         reinvestment_cents                 = reinvestment_cents                 * #{er.rate},
         reinvestment_with_fees_cents       = reinvestment_with_fees_cents       * #{er.rate},
         gross_of_account_entries_cents     = gross_of_account_entries_cents     * #{er.rate},
         net_of_account_entries_cents       = net_of_account_entries_cents       * #{er.rate}"
      )
    end
    # Propagates distribution_amount_cents, completed_distribution_amount_cents, gross_amount_cents
    # to CapitalDistribution, and distribution_amount_cents to CapitalCommitment and Fund
    CapitalDistributionPayment.counter_culture_fix_counts(where: { fund_id: fund.id })
  end

  def reprocess_capital_distributions(fund, old_currency, new_currency, user_id)
    send_notification(
      "#{fund.name}: converting #{fund.capital_distributions.count} capital distribution header amounts",
      user_id
    )
    fund.capital_distributions.pluck(:distribution_date).compact.uniq.each do |date|
      er = ExchangeRate.where(entity_id: fund.entity_id, from: old_currency, to: new_currency)
                       .where(as_of: ..date).last
      next unless er

      # distribution_amount_cents, completed_distribution_amount_cents, gross_amount_cents
      # are counter_culture rollups from CapitalDistributionPayment — already fixed above
      fund.capital_distributions.where(distribution_date: date).update_all(
        "income_cents             = income_cents             * #{er.rate},
         reinvestment_cents       = reinvestment_cents       * #{er.rate},
         cost_of_investment_cents = cost_of_investment_cents * #{er.rate},
         fee_cents                = fee_cents                * #{er.rate}"
      )
    end
  end

  def reprocess_capital_commitments(fund, new_currency, user_id)
    send_notification(
      "#{fund.name}: re-deriving #{fund.capital_commitments.count} capital commitment amounts from folio",
      user_id
    )
    fund.capital_commitments
        .pluck(:folio_currency, :commitment_date)
        .uniq
        .each do |folio_currency, date|
          next if folio_currency.blank? || date.nil?

          scope = fund.capital_commitments.where(folio_currency: folio_currency, commitment_date: date)

          if folio_currency == new_currency
            scope.update_all("orig_committed_amount_cents = orig_folio_committed_amount_cents")
          else
            er = ExchangeRate.where(entity_id: fund.entity_id, from: folio_currency, to: new_currency)
                             .where(as_of: ..date).last
            next unless er

            scope.update_all("orig_committed_amount_cents = orig_folio_committed_amount_cents * #{er.rate}")
          end
        end
    # adjustment_amount_cents is already correct from CommitmentAdjustment.counter_culture_fix_counts above
    fund.capital_commitments.update_all(
      "committed_amount_cents = orig_committed_amount_cents + adjustment_amount_cents"
    )
  end

  def reprocess_capital_calls(fund, old_currency, new_currency, user_id)
    send_notification("#{fund.name}: converting #{fund.capital_calls.count} capital call amounts", user_id)
    # call_amount_cents, collected_amount_cents, capital_fee_cents, other_fee_cents are counter_culture
    # rollups from CapitalRemittance — already fixed by reprocess_remittances above
    fund.capital_calls.pluck(:due_date).compact.uniq.each do |date|
      er = ExchangeRate.where(entity_id: fund.entity_id, from: old_currency, to: new_currency)
                       .where(as_of: ..date).last
      next unless er

      fund.capital_calls.where(due_date: date).update_all(
        "amount_to_be_called_cents = amount_to_be_called_cents * #{er.rate}"
      )
    end
  end

  def log_final_stats(fund, old_currency, new_currency)
    pi_scope    = fund.portfolio_investments.include_proforma
    ratio_dates = fund.fund_ratios.pluck(:end_date).uniq

    Rails.logger.info do
      <<~MSG.squish
        [ChangeFundCurrencyJob] #{fund.name} (id=#{fund.id})
        currency: #{old_currency} → #{new_currency} |
        portfolio_investments: #{pi_scope.where(proforma: false).count} regular + #{pi_scope.where(proforma: true).count} proforma |
        aggregate_portfolio_investments: #{fund.aggregate_portfolio_investments.count} |
        portfolio_attributions: #{fund.portfolio_attributions.count} |
        portfolio_cashflows: #{fund.portfolio_cashflows.count} |
        account_entries: #{fund.account_entries.count} |
        commitment_adjustments: #{fund.commitment_adjustments.count} |
        fund_units: #{fund.fund_units.count} |
        capital_commitments: #{fund.capital_commitments.count} |
        capital_calls: #{fund.capital_calls.count} |
        capital_remittances: #{fund.capital_remittances.count} |
        capital_remittance_payments: #{fund.capital_remittance_payments.count} |
        capital_distributions: #{fund.capital_distributions.count} |
        capital_distribution_payments: #{fund.capital_distribution_payments.count} |
        fund_ratio end_dates requeued: #{ratio_dates.size} (#{ratio_dates.min}..#{ratio_dates.max}) |
        tracking_currency: #{fund.tracking_currency.presence || 'none'}
      MSG
    end
  end

  def recompute_fund_ratios(fund, user_id)
    queued = FundRatioRecompute.call(fund, user_id)
    send_notification("#{fund.name}: recomputing fund ratios for #{queued} date(s)", user_id) if queued.positive?
  end

  # rubocop:enable Rails/SkipsModelValidations
end
