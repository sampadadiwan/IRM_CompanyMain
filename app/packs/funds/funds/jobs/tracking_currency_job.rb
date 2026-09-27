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
      # A fund whose tracking currency is being changed (or whose change failed and awaits a retry)
      # is owned by ChangeTrackingCurrencyJob: converting it here would write amounts at whichever
      # currency happens to be saved mid-change. That job rebuilds it through #rebuild_fund instead.
      funds = funds.without_tracking_currency_change

      funds.each do |fund|
        # The list above was loaded when the sweep started, which can be long before this fund's
        # turn: a change may have been claimed, or even completed, since. Re-read the fund so it is
        # skipped while claimed and otherwise converted at its current tracking currency, not the
        # stale one held in memory.
        fund.reload
        next if fund.tracking_currency_change_pending?

        update_fund(fund, user_id, force: force)
      rescue StandardError => e
        Rails.logger.debug e.backtrace
        send_notification("Error updating tracking currency for fund #{fund.name}: #{e.message}", user_id, :danger)
        @error_msg[:from] = "TrackingCurrencyJob"
        @error_msg[fund.name] = e.message
      end

      @error_msg[:missing_rates] = @missing_rates.to_a if @missing_rates.any?

      send_errors_notification("Errors occurred during Tracking Currency Job", @error_msg, user_id) if @error_msg.present?

      # context: names the job, the acting user, the call site that enqueued it and the
      # arguments it ran with — without it the support inbox gets a bare "Missing rates: ..."
      # with no way to tell which fund, which trigger or which run produced it.
      if @error_msg.present?
        EntityMailer.with(
          error_msg: @error_msg,
          entity_id: entity_id,
          context: error_context(entity_id: entity_id, force: force,
                                 "Fund" => fund_scope_label(fund_id),
                                 "Funds processed" => funds.size)
        ).notify_errors.deliver_now
      end
    end
  end

  # Rebuilds every tracking amount of one fund at the rates for each row's own date, for callers
  # outside #perform (ChangeTrackingCurrencyJob, ChangeFundCurrencyJob).
  #
  # #update_fund reports problems by merging into @error_msg / @missing_rates, which only #perform
  # sets up; calling it on a bare instance raised NoMethodError on nil at the first merge. This sets
  # that state up and hands the problems back, because the caller has to decide whether the rebuild
  # counts as done - a missing rate is rescued per date inside each convert_* method, so no
  # exception reaches the caller when rows are left unconverted.
  #
  # @return [Hash] fund-level errors, plus :missing_rates when any rows could not be converted;
  #   empty when every tracking amount was rebuilt
  def rebuild_fund(fund, user_id)
    @error_msg = {}
    @missing_rates = Set.new
    update_fund(fund, user_id, force: true)
    @error_msg[:missing_rates] = @missing_rates.to_a if @missing_rates.any?
    @error_msg
  end

  # Zeroes every stored tracking amount of the fund, for when its tracking currency is removed (or
  # set to the fund's own currency). Leaving the old figures in place would show them under the
  # fund-currency label, because every tracking monetize falls back to fund.currency.
  #
  # Rollup columns (funds.tracking_*, capital_commitments.tracking_collected/distribution...,
  # aggregate_portfolio_investments.tracking_*) are zeroed directly rather than re-counted: every
  # row they sum is zero after this, so re-counting could only arrive at the same answer, slower.
  def clear_tracking_amounts(fund)
    send_notification("Clearing tracking currency amounts for fund #{fund.name}", nil)
    # account_entries is the largest table: one UPDATE per reporting_date, the same slicing
    # convert_account_entries uses. Not in_batches - its `id IN (...)` UPDATE is planned by MySQL on
    # the partitioned table as a full PRIMARY index scan (EXPLAIN: ~6.9M rows on the production copy)
    # and locks every row it scans, i.e. the whole table, once per batch; on the production copy it
    # failed with "total number of locks exceeds the lock table size" for a 4k-entry fund. Filtering
    # on fund_id + reporting_date uses the fund_id index and prunes to one partition.
    scope = fund.account_entries.where.not(tracking_amount_cents: 0)
    scope.distinct.pluck(:reporting_date).each do |date|
      scope.where(reporting_date: date).update_all(tracking_amount_cents: 0)
    end

    TRACKING_COLUMNS.each do |association, columns|
      fund.public_send(association).update_all(columns.index_with(0))
    end
    fund.portfolio_investments.include_proforma.update_all(tracking_amount_cents: 0, tracking_fmv_cents: 0)
    Fund.where(id: fund.id).update_all(FUND_TRACKING_COLUMNS.index_with(0))
  end

  def update_fund(fund, user_id, force: false)
    Audited.audit_class.as_user("TrackingCurrencyJob") do
      if fund.has_tracking_currency?
        @error_msg.merge!(convert_account_entries(fund, user_id, force: force))
        @error_msg.merge!(convert_remittance_payments(fund, user_id, force: force))
        @error_msg.merge!(convert_remittances(fund, user_id, force: force))
        @error_msg.merge!(convert_distributions(fund, user_id, force: force))
        @error_msg.merge!(convert_commitment_adjustments(fund, user_id, force: force))
        @error_msg.merge!(convert_capital_commitments(fund, user_id, force: force))
        @error_msg.merge!(fix_tracking_rollups(fund))
      end

      # PI entity currency columns run for every fund so cross-fund SUM queries always work.
      @error_msg.merge!(convert_portfolio_investments(fund, force: force))

      send_notification("Tracking/entity currency updated for fund #{fund.name}", user_id)
    end
  end

  # Tracking columns zeroed by #clear_tracking_amounts, per fund association (account_entries and
  # portfolio_investments are handled separately: the first is batched, the second needs
  # include_proforma).
  TRACKING_COLUMNS = {
    capital_remittance_payments: %i[tracking_amount_cents],
    capital_remittances: %i[tracking_call_amount_cents tracking_collected_amount_cents],
    capital_distribution_payments: %i[tracking_net_payable_cents tracking_gross_payable_cents
                                      tracking_reinvestment_with_fees_cents tracking_income_with_fees_cents
                                      tracking_expense_with_fees_cents tracking_tax_with_fees_cents
                                      tracking_display_only_with_fees_cents],
    commitment_adjustments: %i[tracking_amount_cents],
    capital_commitments: %i[tracking_orig_committed_amount_cents tracking_adjustment_amount_cents
                            tracking_committed_amount_cents tracking_collected_amount_cents
                            tracking_distribution_amount_cents],
    aggregate_portfolio_investments: %i[tracking_bought_amount_cents tracking_sold_amount_cents tracking_fmv_cents]
  }.freeze

  FUND_TRACKING_COLUMNS = %i[tracking_committed_amount_cents tracking_call_amount_cents tracking_co_invest_call_amount_cents
                             tracking_collected_amount_cents tracking_distribution_amount_cents].freeze

  private

  # The convert_* methods write with update_all / update_columns, which skip counter_culture, so the
  # rollups those rows feed were left holding whatever they summed before the conversion - on a
  # forced rebuild, figures in the old currency. Re-count the ones fed by remittances and
  # distribution payments (commitment adjustments are re-counted in convert_capital_commitments,
  # portfolio investments in convert_portfolio_investments).
  #
  # `where` is applied to the table being counted INTO, so it is { id: } for the fund itself and
  # { fund_id: } for its commitments; column_name limits each pass to the tracking column, leaving
  # the fund-currency rollups on the same relations alone.
  def fix_tracking_rollups(fund)
    {
      CapitalRemittance => { fund: %w[tracking_call_amount_cents tracking_collected_amount_cents],
                             capital_commitment: %w[tracking_collected_amount_cents] },
      CapitalDistributionPayment => { fund: %w[tracking_distribution_amount_cents],
                                      capital_commitment: %w[tracking_distribution_amount_cents] }
    }.each do |model, relations|
      relations.each do |relation, columns|
        where = relation == :fund ? { id: fund.id } : { fund_id: fund.id }
        columns.each { |column| model.counter_culture_fix_counts(only: relation, column_name: column, where:) }
      end
    end

    # Nothing rolls commitments' tracking_committed_amount_cents up to the fund (the counter_culture
    # on CapitalCommitment covers committed_amount_cents only), so the fund header's "Tracking
    # Committed" was never populated. Sum it here, where every commitment's value has just been set.
    Fund.where(id: fund.id).update_all(tracking_committed_amount_cents: fund.capital_commitments.sum(:tracking_committed_amount_cents))
    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    { "#{fund.name}: Tracking rollups" => e.message }
  end

  def convert_account_entries(fund, user_id, force: false)
    send_notification("Updating tracking currency for account entries", user_id)
    scope = fund.account_entries
    # By default, we only process new entries (tracking_amount_cents == 0)
    scope = scope.where(tracking_amount_cents: 0) unless force

    # Batch process by reporting_date to minimize exchange rate lookups.
    # distinct.pluck dedups in SQL instead of materializing one Date per ledger row
    scope.distinct.pluck(:reporting_date).compact.each do |date|
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
      record_missing_rate("Account Entries", fund, date, scope.where(reporting_date: date))
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
      record_missing_rate("Remittance Payments", fund, date, scope.where(payment_date: date))
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
      record_missing_rate("Remittances", fund, date, scope.where(remittance_date: date))
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
      # All tracking amounts are converted at the same payment_date rate
      scope.where(payment_date: date).update_all(
        "tracking_net_payable_cents = net_payable_cents * #{rate},
         tracking_gross_payable_cents = gross_payable_cents * #{rate},
         tracking_reinvestment_with_fees_cents = reinvestment_with_fees_cents * #{rate},
         tracking_income_with_fees_cents = income_with_fees_cents * #{rate},
         tracking_expense_with_fees_cents = expense_with_fees_cents * #{rate},
         tracking_tax_with_fees_cents = tax_with_fees_cents * #{rate},
         tracking_display_only_with_fees_cents = display_only_with_fees_cents * #{rate}"
      )
    rescue StandardError
      record_missing_rate("Distributions", fund, date, scope.where(payment_date: date))
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
      record_missing_rate("Commitment Adjustments", fund, date, scope.where(as_of: date))
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
      record_missing_rate("Capital Commitments", fund, date, scope.where(commitment_date: date))
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
      @missing_rates << "Portfolio Investment (#{pi.id}) in #{fund_label(fund)}: #{e.message}"
      Rails.logger.error "Error updating PI #{pi.id}: #{e.message}"
    end

    PortfolioInvestment.counter_culture_fix_counts(where: { fund_id: fund.id })

    {}
  rescue StandardError => e
    Rails.logger.debug e.backtrace
    { "#{fund.name}: Portfolio Investments" => e.message }
  end

  # One missing-rate line for the error email. The fund and the number of rows left unconverted
  # are part of the message because the report is read in a support inbox with no other context:
  # "Capital Commitments: USD->INR on 1899-12-30" names neither the fund that holds the bad date
  # nor how much is affected.
  #
  # `scope` arrives as an unexecuted relation and is counted here, on the failure path only, once
  # per (kind, date) — a COUNT with the fund and date already filtered, never a row load. If that
  # COUNT itself fails the line is still recorded without the tally: the point of this method is
  # to make sure the missing rate gets reported, and a decoration must not be able to lose it.
  def record_missing_rate(label, fund, date, scope = nil)
    rows = begin
      scope&.count
    rescue StandardError => e
      Rails.logger.error "Could not count rows for missing rate #{label} on #{date}: #{e.message}"
      nil
    end
    tally = rows ? " (#{rows} row(s) not converted)" : ""
    @missing_rates << "#{label}: #{fund_label(fund)} #{fund.currency}->#{fund.tracking_currency} " \
                      "on #{date}#{tally}"
  end

  def fund_label(fund)
    "#{fund.name} (##{fund.id})"
  end

  # What this run covered, for the error email: one named fund, or the whole scheduled sweep.
  def fund_scope_label(fund_id)
    return "All funds in scope" if fund_id.blank?

    fund = Fund.find_by(id: fund_id)
    fund ? fund_label(fund) : "##{fund_id} (fund not found)"
  end

  # Returns the exchange rate multiplier from fund currency to the target currency.
  # Returns 1 when currencies are the same to avoid a DB lookup.
  def entity_rate_for(fund, target_currency, date)
    return 1 if fund.currency == target_currency

    er = fund.get_exchange_rate(fund.currency, target_currency, date)
    unless er
      @missing_rates << "Portfolio Investments: #{fund_label(fund)} #{fund.currency}->#{target_currency} on #{date}"
      return nil
    end
    er.rate
  end
  # rubocop:enable Rails/SkipsModelValidations
end
