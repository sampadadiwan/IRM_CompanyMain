class FundRatioCalcs
  # rubocop:disable Metrics/CyclomaticComplexity
  # rubocop:disable Metrics/PerceivedComplexity
  # rubocop:disable Metrics/MethodLength
  def xirr(entity:, net_irr: false, return_cash_flows: false,
           adjustment_cash: 0, scenarios: nil, use_tracking_currency: false)
    cf = XirrCashflow.new
    entity_type = entity.is_a?(Fund) ? "fund" : "capital_commitment"
    Rails.logger.debug { "Computing XIRR for #{entity_type}: #{entity} on #{@end_date}" }

    # Capital Remittance Payments
    Rails.logger.debug { "Adding capital_remittance_payments for #{entity_type}: #{entity} on #{@end_date}" }
    entity.capital_remittance_payments.includes(:capital_remittance).where(capital_remittance_payments: { payment_date: ..@end_date }).find_each do |cr|
      if use_tracking_currency
        cf << XirrTransaction.new(-1 * cr.tracking_amount_cents, date: cr.payment_date, notes: "#{cr.capital_remittance.investor_name} Remittance #{cr.id}") if cr.tracking_amount_cents != 0
      elsif cr.amount_cents != 0
        cf << XirrTransaction.new(-1 * cr.amount_cents, date: cr.payment_date, notes: "#{cr.capital_remittance.investor_name} Remittance #{cr.id}")
      end
    end

    # Capital Distribution Payments
    Rails.logger.debug { "Adding capital_distribution_payments for #{entity_type}: #{entity} on #{@end_date}" }
    entity.capital_distribution_payments.includes(:investor).where(capital_distribution_payments: { payment_date: ..@end_date }).find_each do |cdp|
      if use_tracking_currency
        cf << XirrTransaction.new(cdp.tracking_gross_payable_cents, date: cdp.payment_date, notes: "#{cdp.investor.investor_name} Gross Distribution #{cdp.id}") if cdp.tracking_gross_payable_cents != 0
        cf << XirrTransaction.new(-1 * cdp.tracking_reinvestment_with_fees_cents, date: cdp.payment_date, notes: "#{cdp.investor.investor_name} Reinvestment from Distribution #{cdp.id}") if cdp.tracking_reinvestment_with_fees_cents != 0
      else
        cf << XirrTransaction.new(cdp.gross_payable_cents, date: cdp.payment_date, notes: "#{cdp.investor.investor_name} Gross Distribution #{cdp.id}") if cdp.gross_payable_cents != 0
        cf << XirrTransaction.new(-1 * cdp.reinvestment_with_fees_cents, date: cdp.payment_date, notes: "#{cdp.investor.investor_name} Reinvestment from Distribution #{cdp.id}") if cdp.reinvestment_with_fees_cents != 0
      end
    end

    # Additional Financial Metrics
    Rails.logger.debug { "Adding financial metrics for #{entity_type}: #{entity} on #{@end_date}" }
    fmv = entity.is_a?(Fund) ? fmv_on_date(scenarios:) : fmv_on_date
    cih = cash_in_hand_cents
    nca = net_current_assets_cents
    ec = estimated_carry_cents
    ac = adjustment_cash

    if use_tracking_currency
      # get the fund
      fund = entity.is_a?(Fund) ? entity : entity.fund
      # Convert to tracking currency
      tracking_exchange_rate = entity.get_exchange_rate(fund.currency, fund.tracking_currency, @end_date)
      raise "No exchange rate found for #{fund.currency} to #{fund.tracking_currency} on #{@end_date}" unless tracking_exchange_rate

      fmv *= tracking_exchange_rate.rate
      cih *= tracking_exchange_rate.rate
      nca *= tracking_exchange_rate.rate
      ec *= tracking_exchange_rate.rate
      ac *= tracking_exchange_rate.rate
    end

    cf << XirrTransaction.new(fmv, date: @end_date, notes: "FMV") if fmv != 0
    cf << XirrTransaction.new(cih, date: @end_date, notes: "Cash in Hand") if cih != 0
    cf << XirrTransaction.new(nca, date: @end_date, notes: "Net Current Assets") if nca != 0
    cf << XirrTransaction.new(-1 * ec, date: @end_date, notes: "Estimated Carry") if net_irr && ec != 0
    cf << XirrTransaction.new(ac, date: @end_date, notes: "Adjustment Cash") if ac != 0

    Rails.logger.debug { "#{entity_type}.xirr cf: #{cf}" }
    cf.each { |cash_flow| Rails.logger.debug "#{cash_flow.date}, #{cash_flow.amount}, #{cash_flow.notes}" }

    lxirr = XirrApi.new.xirr(cf, "xirr_#{entity_type}_#{entity.id}_#{@end_date}") || 0
    Rails.logger.debug { "#{entity_type}.xirr irr: #{lxirr}" }

    return_cash_flows ? [(lxirr * 100).round(2), cf] : (lxirr * 100).round(2)
  end
  # rubocop:enable Metrics/CyclomaticComplexity
  # rubocop:enable Metrics/PerceivedComplexity
  # rubocop:enable Metrics/MethodLength
end
