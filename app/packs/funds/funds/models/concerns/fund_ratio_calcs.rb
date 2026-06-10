class FundRatioCalcs
  # rubocop:disable Metrics/CyclomaticComplexity
  # rubocop:disable Metrics/PerceivedComplexity
  # rubocop:disable Metrics/MethodLength
  attr_accessor :model, :portfolio_company_id

  delegate :capital_remittance_payments, to: :model
  delegate :capital_distribution_payments, to: :model
  delegate :aggregate_portfolio_investments, to: :model
  delegate :portfolio_investments, to: :model
  delegate :ratio_formulas, to: :model

  def xirr(model:, net_irr: false, return_cash_flows: false,
           adjustment_cash: 0, scenarios: nil, use_tracking_currency: false)
    @model = model
    cf = XirrCashflow.new
    model_type = model.is_a?(Fund) ? "fund" : "capital_commitment"
    Rails.logger.debug { "Computing XIRR for #{model_type}: #{model} on #{@end_date}" }

    # Capital Remittance Payments
    Rails.logger.debug { "Adding capital_remittance_payments for #{model_type}: #{model} on #{@end_date}" }
    # When computing ratios at kyc level, InvestorKycCalcs overrides this method to return KYC-scoped payments
    capital_remittance_payments.where(capital_remittance_payments: { payment_date: ..@end_date }).find_each do |cr|
      if use_tracking_currency
        # Add remittance payment in tracking currency if amount is not zero
        cf << XirrTransaction.new(-1 * cr.tracking_amount_cents, date: cr.payment_date, notes: "Remittance #{cr.id}") if cr.tracking_amount_cents != 0
      elsif cr.amount_cents != 0
        # Add remittance payment in original currency if amount is not zero
        cf << XirrTransaction.new(-1 * cr.amount_cents, date: cr.payment_date, notes: "Remittance #{cr.id}")
      end
    end

    # Capital Distribution Payments
    Rails.logger.debug { "Adding capital_distribution_payments for #{model_type}: #{model} on #{@end_date}" }
    # When computing ratios at kyc level, InvestorKycCalcs overrides this method to return KYC-scoped payments
    capital_distribution_payments.where(capital_distribution_payments: { payment_date: ..@end_date }).find_each do |cdp|
      if use_tracking_currency
        # Add gross distribution payment in tracking currency if amount is not zero
        cf << XirrTransaction.new(cdp.tracking_gross_payable_cents, date: cdp.payment_date, notes: "Gross Payable from Distribution #{cdp.id}") if cdp.tracking_gross_payable_cents != 0
        # Add reinvestment from distribution in tracking currency if amount is not zero
        cf << XirrTransaction.new(-1 * cdp.tracking_reinvestment_with_fees_cents, date: cdp.payment_date, notes: "Reinvestment from Distribution #{cdp.id}") if cdp.tracking_reinvestment_with_fees_cents != 0
      else
        # Add gross distribution payment in original currency if amount is not zero
        cf << XirrTransaction.new(cdp.gross_payable_cents, date: cdp.payment_date, notes: "Gross Payable from Distribution #{cdp.id}") if cdp.gross_payable_cents != 0
        # Add reinvestment from distribution in original currency if amount is not zero
        cf << XirrTransaction.new(-1 * cdp.reinvestment_with_fees_cents, date: cdp.payment_date, notes: "Reinvestment from Distribution #{cdp.id}") if cdp.reinvestment_with_fees_cents != 0
      end
    end

    apply_formula_cashflows(cf, "XIRR", use_tracking_currency)

    # Additional Financial Metrics
    Rails.logger.debug { "Adding financial metrics for #{model_type}: #{model} on #{@end_date}" }
    fmv = model.is_a?(Fund) ? fmv_on_date(scenarios:) : fmv_on_date
    cih = cash_in_hand_cents
    nca = net_current_assets_cents
    ec = estimated_carry_cents
    ac = adjustment_cash

    if use_tracking_currency
      # get the fund
      fund = model.is_a?(Fund) ? model : model.fund
      # Convert to tracking currency
      tracking_exchange_rate = model.get_exchange_rate(fund.currency, fund.tracking_currency, @end_date)
      raise "No exchange rate found for #{fund.currency} to #{fund.tracking_currency} on #{@end_date}" unless tracking_exchange_rate

      # Adjust financial metrics to tracking currency
      fmv *= tracking_exchange_rate.rate
      cih *= tracking_exchange_rate.rate
      nca *= tracking_exchange_rate.rate
      ec *= tracking_exchange_rate.rate
      ac *= tracking_exchange_rate.rate
    end

    # Add financial metrics to cash flow if they are not zero
    # if adjustment cash is provided, FMV is considered part of it
    cf << XirrTransaction.new(fmv, date: @end_date, notes: "FMV") if fmv != 0 && adjustment_cash.zero?
    cf << XirrTransaction.new(cih, date: @end_date, notes: "Cash in Hand") if cih != 0
    cf << XirrTransaction.new(nca, date: @end_date, notes: "Net Current Assets") if nca != 0
    cf << XirrTransaction.new(-1 * ec, date: @end_date, notes: "Estimated Carry") if net_irr && ec != 0
    cf << XirrTransaction.new(ac, date: @end_date, notes: "Adjustment Cash") if ac != 0

    Rails.logger.debug { "#{model_type}.xirr cf: #{cf}" }
    cf.each { |cash_flow| Rails.logger.debug "#{cash_flow.date}, #{cash_flow.amount}, #{cash_flow.notes}" }

    # Calculate XIRR using the cash flow
    lxirr = XirrApi.new.xirr(cf, "xirr_#{model_type}_#{model.id}_#{@end_date}") || 0
    Rails.logger.debug { "#{model_type}.xirr irr: #{lxirr}" }

    # binding.pry
    # Return XIRR and optionally the cash flows
    return_cash_flows ? [(lxirr * 100).round(2), cf] : (lxirr * 100).round(2)
  end

  # rubocop:enable Metrics/CyclomaticComplexity
  # rubocop:enable Metrics/PerceivedComplexity
  # rubocop:enable Metrics/MethodLength

  # Calculates the Multiple on Invested Capital (MOIC) for the given model.
  # MOIC is the ratio of total returns (from sales and FMV) to total invested capital.
  # Optionally includes synthetic investments and supports tracking currency conversion.
  # Returns the MOIC value rounded to 2 decimals, and optionally the cash flows.
  def moic(model:, synthetic_investments: [], use_tracking_currency: false, return_cash_flows: false)
    @model = model
    total_amount, total_bought, cf = moic_components(synthetic_investments:, use_tracking_currency:, return_cash_flows:)

    # Clear cash flows if not requested to return them
    cf = nil unless return_cash_flows

    # Return 0 if no investments were bought
    return 0, cf if total_bought.zero?

    # Return MOIC as ratio rounded to 2 decimals, and cash flows if requested
    [(total_amount / total_bought.to_f).round(2), cf]
  end

  def moic_components(synthetic_investments: [], use_tracking_currency: false, return_cash_flows: false)
    cf = XirrCashflow.new

    total_bought = 0.to_d
    total_sold = 0.to_d
    total_fmv = 0.to_d

    # Process portfolio investments up to the end date
    portfolio_investments.where(portfolio_investments: { investment_date: ..@end_date }).includes(:fund, :investment_instrument).find_each do |pi|
      pi = pi.as_of(@end_date)
      amount_cents = convert_amount(@model, pi.amount_cents, pi.investment_date, use_tracking_currency)
      if pi.quantity.positive?
        # Positive quantity: investment (buy)
        cf << XirrTransaction.new(amount_cents, date: pi.investment_date, notes: pi.to_s)
        total_bought += amount_cents
      elsif pi.quantity.negative?
        # Negative quantity: divestment (sell)
        cf << XirrTransaction.new(-1 * amount_cents, date: pi.investment_date, notes: pi.to_s)
        total_sold += amount_cents
      end
      fmv_cents = convert_amount(@model, pi.fmv_cents, @end_date, use_tracking_currency)
      total_fmv += fmv_cents
    end

    # Process synthetic investments if provided
    if synthetic_investments.present?
      temp_synthetic_investments = synthetic_investments.select { |si| si.investment_date <= @end_date }

      temp_synthetic_investments.each do |pi|
        amount_cents = convert_amount(@model, pi.amount_cents, pi.investment_date, use_tracking_currency)
        if pi.quantity.positive?
          # Positive quantity: synthetic investment (buy)
          cf << XirrTransaction.new(amount_cents, date: pi.investment_date, notes: pi.to_s)
          total_bought += amount_cents
        elsif pi.quantity.negative?
          # Negative quantity: synthetic divestment (sell)
          cf << XirrTransaction.new(-1 * amount_cents, date: pi.investment_date, notes: pi.to_s)
          total_sold += amount_cents
        end
        fmv_cents = pi.compute_fmv_cents_on(pi.investment_date)
        total_fmv += convert_amount(@model, fmv_cents, @end_date, use_tracking_currency)
      end
    end

    # Calculate total amount: if synthetic investments present, use total_sold; else, total_fmv + total_sold
    total_amount = synthetic_investments.present? ? total_sold : (total_fmv + total_sold)
    # Only consider FMV if no synthetic investments are provided
    cf << XirrTransaction.new(total_fmv, date: @end_date, notes: "FMV") if synthetic_investments.blank?

    total_amount, total_bought = apply_static_formulas('MOIC', total_amount, total_bought, use_tracking_currency)

    [total_amount, total_bought, cf]
  end

  # Helper for currency conversion
  def convert_amount(model, amount_cents, date, use_tracking_currency)
    return amount_cents unless use_tracking_currency

    tracking_exchange_rate = model.get_exchange_rate(model.currency, model.tracking_currency, date)
    raise "No exchange rate found for #{model.currency} to #{model.tracking_currency} on #{date}" unless tracking_exchange_rate

    (amount_cents * tracking_exchange_rate.rate).round
  end

  private

  def apply_formula_cashflows(cf, ratio_name, use_tracking_currency)
    formulas = ratio_formulas.where(action: %w[add_cashflow reduce_cashflow])
    formulas.each do |formula|
      next unless Array(formula.ratios).include?(ratio_name)

      entries = get_ratio_formula_entries(formula)
      entries.each do |ae|
        amount = use_tracking_currency ? ae.tracking_amount_cents : ae.amount_cents
        multiplier = formula.action == 'add_cashflow' ? 1 : -1
        cf << XirrTransaction.new(multiplier * amount, date: ae.reporting_date, notes: "#{formula.action_text} #{ae.name}")
      end
    end
  end

  def get_ratio_formula_entries(formula)
    scope = AccountEntry.where(entity_id: @model.entity_id, fund_id: (@model.is_a?(Fund) ? @model.id : @model.fund_id))
                        .where(name: formula.account_entry_names, reporting_date: ..@end_date, cumulative: false)

    case formula.level
    when 'Fund'
      scope = scope.where(capital_commitment_id: nil)
    when 'Folio'
      return [] unless @model.is_a?(CapitalCommitment)

      # When computing ratios at kyc level we have multiple folio ids - check InvestorKycCalcs init
      @folio_ids ||= @model.folio_id
      scope = scope.where(folio_id: @folio_ids)
    when 'PortfolioCompany'
      # This level might need specific logic depending on where it's called
      # For now, if we have a portfolio_company context, we filter by it
      if @portfolio_company_id
        scope = scope.where(parent_type: 'Investor', parent_id: @portfolio_company_id)
      else
        return []
      end
    end

    if formula.period == 'as_on'
      if @compute_at_kyc_level
        latest_per_commitment(scope)
      else
        entry = scope.order(reporting_date: :desc).first
        entry ? [entry] : []
      end
    else
      scope.to_a
    end
  end

  # protected so FundRatioMultiFundCalcs can call it on FundPortfolioCalcs instances
  # (private would block any explicit-receiver call from sibling subclasses).
  protected

  def apply_static_formulas(ratio_name, numerator, denominator, use_tracking_currency)
    formulas = ratio_formulas.where(action: %w[add_numerator reduce_numerator add_denominator reduce_denominator])
    formulas.each do |formula|
      next unless Array(formula.ratios).include?(ratio_name)

      entries = get_ratio_formula_entries(formula)
      entries.each do |ae|
        amount = use_tracking_currency ? ae.tracking_amount_cents : ae.amount_cents
        case formula.action
        when 'add_numerator'
          numerator += amount
        when 'reduce_numerator'
          numerator -= amount
        when 'add_denominator'
          denominator += amount
        when 'reduce_denominator'
          denominator -= amount
        end
      end
    end
    [numerator, denominator]
  end

  # Gets the latest account entry per commitment by date and ID.
  # Handles the case where multiple entries exist for the same commitment on the same date
  # by selecting only the entry with the highest ID.
  #
  # @param account_entries_relation [ActiveRecord::Relation] The filtered account entries relation
  # @return [ActiveRecord::Relation] The latest account entries per commitment
  def latest_per_commitment(account_entries_relation)
    latest_per_commitment = account_entries_relation.select('capital_commitment_id, MAX(reporting_date) as max_reporting_date')
                                                    .group(:capital_commitment_id)
    entries_at_max_date = account_entries_relation.where("(capital_commitment_id, reporting_date) IN (SELECT capital_commitment_id, max_reporting_date FROM (#{latest_per_commitment.to_sql}) as sub)")
    max_ids_per_commitment = entries_at_max_date.select('capital_commitment_id, MAX(id) as max_id')
                                                .group(:capital_commitment_id)
    account_entries_relation.where("(capital_commitment_id, id) IN (SELECT capital_commitment_id, max_id FROM (#{max_ids_per_commitment.to_sql}) as sub)")
  end
end
