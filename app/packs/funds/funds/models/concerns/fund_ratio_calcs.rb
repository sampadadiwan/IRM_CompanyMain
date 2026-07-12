class FundRatioCalcs
  attr_accessor :model, :portfolio_company_id

  delegate :capital_remittance_payments, to: :model
  delegate :capital_distribution_payments, to: :model
  delegate :aggregate_portfolio_investments, to: :model
  delegate :portfolio_investments, to: :model
  delegate :ratio_formulas, to: :model

  def xirr(model:, net_irr: false, return_cash_flows: false,
           adjustment_cash: 0, scenarios: nil, use_tracking_currency: false, label: nil, level: nil)
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

    skip_portfolio_fmv = apply_formula_cashflows(cf, "XIRR", use_tracking_currency, level, label: label)

    # Additional Financial Metrics
    Rails.logger.debug { "Adding financial metrics for #{model_type}: #{model} on #{@end_date}" }

    # skip_portfolio_fmv on a matching ratio formula means the FMV computed here should not be
    # added to the cash flow at all - the formula's own account entries stand in for it instead
    fmv = if skip_portfolio_fmv
            0
          else
            model.is_a?(Fund) ? fmv_on_date(scenarios:) : fmv_on_date
          end
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

  # Calculates the Multiple on Invested Capital (MOIC) for the given model.
  # MOIC is the ratio of total returns (from sales and FMV) to total invested capital.
  # Optionally includes synthetic investments and supports tracking currency conversion.
  # Returns the MOIC value rounded to 2 decimals, and optionally the cash flows.
  def moic(model:, synthetic_investments: [], use_tracking_currency: false, return_cash_flows: false, label: nil, level: nil)
    @model = model
    total_amount, total_bought, cf = moic_components(synthetic_investments:, use_tracking_currency:, return_cash_flows:, label: label, level: level)

    # Clear cash flows if not requested to return them
    cf = nil unless return_cash_flows

    # Return 0 if no investments were bought
    return 0, cf if total_bought.zero?

    # Return MOIC as ratio rounded to 2 decimals, and cash flows if requested
    [(total_amount / total_bought.to_f).round(2), cf]
  end

  def moic_components(synthetic_investments: [], use_tracking_currency: false, return_cash_flows: false, label: nil, level: nil)
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

    # If synthetic investments are provided, update FMV to 0
    # This helps when formulas are set to skip FMV
    # as fmv will be subtracted on skip_portfolio_fmv, when fmv is 0, 0 will be subtracted and the numerator will be correct
    # as fmv is not considered in computation with synthetic investments
    total_fmv = 0 if synthetic_investments.present?

    # Calculate total amount: if synthetic investments present, use total_sold; else, total_fmv + total_sold
    total_amount = synthetic_investments.present? ? total_sold : (total_fmv + total_sold)
    # Only consider FMV if no synthetic investments are provided
    cf << XirrTransaction.new(total_fmv, date: @end_date, notes: "FMV") if synthetic_investments.blank?

    total_amount, total_bought = apply_static_formulas('MOIC', total_amount, total_bought, use_tracking_currency, level, label: label, fmv: total_fmv)

    cf = nil unless return_cash_flows
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

  # Returns whether any matching formula has skip_portfolio_fmv set, so callers can leave the
  # code-computed FMV out of the cash flow (it's expected to be represented by these formula
  # entries instead).
  def apply_formula_cashflows(cf, ratio_name, use_tracking_currency, level, label: nil)
    # filter formulas by ratio_name, action, and label (nil label means unlabeled formulas)
    formulas = ratio_formulas.where(action: %w[add_cashflow reduce_cashflow], ratio: ratio_name, label: label)
    # filter formulas by level if provided
    formulas = formulas.where(level: level) if level.present?
    skip_portfolio_fmv = formulas.any?(&:skip_portfolio_fmv)
    formulas.each do |formula|
      entries = get_ratio_formula_entries(formula)
      entries.each do |ae|
        amount = use_tracking_currency ? ae.tracking_amount_cents : ae.amount_cents
        multiplier = formula.action == 'add_cashflow' ? 1 : -1
        cf << XirrTransaction.new(multiplier * amount, date: ae.reporting_date, notes: "#{formula.action_text} #{ae.name}")
      end
    end
    skip_portfolio_fmv
  end

  def get_ratio_formula_entries(formula)
    scope = AccountEntry.where(entity_id: @model.entity_id, fund_id: (@model.is_a?(Fund) ? @model.id : @model.fund_id))
                        .where(reporting_date: ..@end_date)

    # filter AEs by account_entry_names if provided in the formula
    scope = scope.where(name: formula.account_entry_names) if formula.account_entry_names.present?
    # cumulative is false by default (also maintains backward compatibility)
    cumulative = formula.cumulative.presence || false
    scope = scope.where(cumulative: cumulative)
    # filter AEs by entry_type if provided in the formula
    scope = scope.where(entry_type: formula.entry_type.split(",").map(&:strip)) if formula.entry_type.present?

    case formula.level
    when 'Fund'
      scope = scope.where(capital_commitment_id: nil)
    when 'Folio'
      return [] unless @model.is_a?(CapitalCommitment)

      # When computing ratios at kyc level we have multiple folio ids - check InvestorKycCalcs init
      @folio_ids ||= @model.folio_id
      scope = scope.where(folio_id: @folio_ids)
    end

    if formula.level == 'PortfolioCompany'
      return [] unless @portfolio_company_id

      # AEs for a PortfolioCompany are either linked to its PortfolioInvestments or directly
      # to the Investor (parent_id = portfolio_company_id). parent_type narrows to one of these.
      investment_ids = PortfolioInvestment.where(portfolio_company_id: @portfolio_company_id, fund_id: formula.fund_id, entity_id: @model.entity_id).select(:id)
      investment_scope = scope.where(parent_type: 'PortfolioInvestment', parent_id: investment_ids)
      investor_scope = scope.where(parent_type: 'Investor', parent_id: @portfolio_company_id)

      # strip so a stray space in the configured value still matches (parent_type is a single
      # class here, never comma-separated); blank means include both scopes.
      case formula.parent_type&.strip.presence
      when nil then scope = investment_scope.or(investor_scope)
      when 'PortfolioInvestment' then scope = investment_scope
      when 'Investor' then scope = investor_scope
      else raise "Unknown parent_type #{formula.parent_type} for formula #{formula.id}"
      end
    elsif formula.parent_type.present?
      # non-PortfolioCompany levels may list several parent types, comma-separated
      scope = scope.where(parent_type: formula.parent_type.split(",").map(&:strip))
    end

    if formula.period == 'as_on'
      if @compute_at_kyc_level
        latest_per_commitment(scope)
      else
        # when there are multiple ae names - take the last of each name
        latest_per_name(scope).to_a
      end
    else
      scope.to_a
    end
  end

  # protected so FundRatioMultiFundCalcs can call it on FundPortfolioCalcs instances
  # (private would block any explicit-receiver call from sibling subclasses).
  protected

  # fmv: the code-computed FMV already folded into `numerator` by the caller (0 if not
  # applicable to this ratio). When a matching formula has skip_portfolio_fmv set, it is backed
  # out of the numerator once, regardless of how many such formulas match.
  def apply_static_formulas(ratio_name, numerator, denominator, use_tracking_currency, level, label: nil, fmv: 0)
    formulas = ratio_formulas.where(action: %w[add_numerator reduce_numerator add_denominator reduce_denominator], ratio: ratio_name, label: label)
    formulas = formulas.where(level: level) if level.present?
    fmv_reduced = false
    formulas.each do |formula|
      if formula.skip_portfolio_fmv && !fmv_reduced
        numerator -= fmv
        fmv_reduced = true
      end
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

  # Used for formula period "as_on" at the KYC level, where a single ratio can span multiple
  # capital commitments (e.g. an investor with several folios in the same fund). We need one
  # "as of" entry per (commitment, name) pair rather than a single latest entry overall, since a
  # commitment can have several distinct account entry names (e.g. from account_entry_names on
  # the formula) each with their own timeline.
  #
  # Resolved in three steps to emulate "latest row per group" in SQL:
  #   1. max_reporting_date per (capital_commitment_id, name)
  #   2. all entries that fall on that max date (there can be more than one on the same day)
  #   3. of those, keep only the highest id (arbitrary but deterministic tiebreaker)
  # The final filter only needs (capital_commitment_id, id) because id alone already pins a
  # unique row; name doesn't need to be repeated there.
  #
  # @param account_entries_relation [ActiveRecord::Relation] The filtered account entries relation
  # @return [ActiveRecord::Relation] The latest account entries per (commitment, name)
  def latest_per_commitment(account_entries_relation)
    latest_per_commitment = account_entries_relation.select('capital_commitment_id, name, MAX(reporting_date) as max_reporting_date')
                                                    .group(:capital_commitment_id, :name)
    entries_at_max_date = account_entries_relation.where("(capital_commitment_id, name, reporting_date) IN (SELECT capital_commitment_id, name, max_reporting_date FROM (#{latest_per_commitment.to_sql}) as sub)")
    max_ids_per_commitment = entries_at_max_date.select('capital_commitment_id, name, MAX(id) as max_id')
                                                .group(:capital_commitment_id, :name)
    account_entries_relation.where("(capital_commitment_id, id) IN (SELECT capital_commitment_id, max_id FROM (#{max_ids_per_commitment.to_sql}) as sub)")
  end

  # Same "latest row per group" logic as latest_per_commitment above, but grouped only by
  # name (not capital_commitment_id) since this is used outside the KYC level, where a formula's
  # account entries aren't scoped to individual commitments. Needed because a formula can list
  # several account_entry_names, and formula period "as_on" should take the latest entry for
  # each of those names independently rather than a single latest entry across all of them.
  #
  # @param account_entries_relation [ActiveRecord::Relation] The filtered account entries relation
  # @return [ActiveRecord::Relation] The latest account entries per name
  def latest_per_name(account_entries_relation)
    latest_per_name = account_entries_relation.select('name, MAX(reporting_date) as max_reporting_date')
                                              .group(:name)
    entries_at_max_date = account_entries_relation.where("(name, reporting_date) IN (SELECT name, max_reporting_date FROM (#{latest_per_name.to_sql}) as sub)")
    max_ids_per_name = entries_at_max_date.select('name, MAX(id) as max_id')
                                          .group(:name)
    account_entries_relation.where("(name, id) IN (SELECT name, max_id FROM (#{max_ids_per_name.to_sql}) as sub)")
  end
end
