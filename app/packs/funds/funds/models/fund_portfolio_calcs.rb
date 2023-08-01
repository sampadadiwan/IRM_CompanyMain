class FundPortfolioCalcs
  def initialize(fund, end_date)
    @fund = fund
    @end_date = end_date
  end

  def total_investment_costs_cents
    @total_investment_costs_cents ||= PortfolioInvestment.total_investment_costs_cents(@fund, @end_date)
  end

  def fmv_cents
    @fmv_cents ||= PortfolioInvestment.fmv_cents(@fund, @end_date)
  end

  def total_investment_sold_cents
    @total_investment_sold_cents ||= PortfolioInvestment.total_investment_sold_cents(@fund, @end_date)
  end

  def distribution_cents
    @distribution_cents ||= @fund.capital_distribution_payments.completed.where(payment_date: ..@end_date).sum(:amount_cents)
  end

  def reinvested_capital_cents
    total_investment_sold_cents - distribution_cents
  end

  def cash_in_hand_cents
    @cash_in_hand_cents ||= begin
      ae = @fund.fund_account_entries.where(name: "Cash In Hand", reporting_date: ..@end_date).order(reporting_date: :asc).last
      ae&.amount_cents || 0
    end
  end

  def net_current_assets_cents
    @net_current_assets_cents ||= begin
      ae = @fund.fund_account_entries.where(name: "Net Current Assets", reporting_date: ..@end_date).order(reporting_date: :asc).last
      ae&.amount_cents || 0
    end
  end

  def estimated_carry_cents
    @estimated_carry_cents ||= begin
      ae = @fund.fund_account_entries.where(name: "Estimated Carry", reporting_date: ..@end_date).order(reporting_date: :asc).last
      ae&.amount_cents || 0
    end
  end

  def total_value_cents
    fmv_cents + distribution_cents + cash_in_hand_cents + net_current_assets_cents
  end

  def net_total_value_cents
    total_value_cents - estimated_carry_cents
  end

  def collected_cents
    @collected_cents ||= @fund.capital_remittances.verified.where(payment_date: ..@end_date).sum(:collected_amount_cents)
  end

  def committed_cents
    @committed_cents ||= @fund.capital_commitments.sum(:committed_amount_cents)
  end

  def dpi
    cc = collected_cents
    cc.positive? ? (distribution_cents / cc) : 0
  end

  def rvpi
    collected_cents.positive? ? (fmv_cents / collected_cents).round(2) : 0
  end

  def tvpi
    dpi + rvpi
  end

  def fund_utilization
    committed_cents.positive? ? (total_investment_costs_cents / committed_cents) : 0
  end

  def portfolio_value_to_cost
    total_investment_costs_cents.positive? ? fmv_cents / total_investment_costs_cents : 0
  end

  # TODO
  def paid_in_to_committed_capital
    committed_cents.positive? ? collected_cents / committed_cents : 0
  end

  def gross_portfolio_irr
    @gross_portfolio_irr ||= begin
      cf = Xirr::Cashflow.new

      @fund.portfolio_investments.buys.where(investment_date: ..@end_date).each do |buy|
        cf << Xirr::Transaction.new(-1 * buy.amount_cents, date: buy.investment_date, notes: "Bought Amount") if buy.amount_cents.positive?
      end

      @fund.portfolio_investments.sells.where(investment_date: ..@end_date).each do |sell|
        cf << Xirr::Transaction.new(sell.amount_cents, date: sell.investment_date, notes: "Sold Amount") if sell.amount_cents.positive?
      end

      cf << Xirr::Transaction.new(fmv_on_date, date: @end_date, notes: "FMV on Date") if fmv_on_date.positive?

      lxirr = XirrApi.new.xirr(cf, "gross_portfolio_irr")
      (lxirr * 100).round(2)
    end
  end

  # Compute the XIRR for each portfolio company
  def portfolio_company_irr(return_cash_flows: false)
    @portfolio_companies_map ||= {}

    if @portfolio_companies_map.empty?
      # Group all fund investments by the portfolio_company
      # @fund.portfolio_investments.pool.where(investment_date: ..@end_date).order(investment_date: :asc).group_by(&:portfolio_company_id)

      @fund.portfolio_investments.select { |pi| pi.Pool? && pi.investment_date <= @end_date }.sort_by(&:investment_date).group_by(&:portfolio_company_id).each do |portfolio_company_id, portfolio_investments|
        cf = Xirr::Cashflow.new
        # Get the buy cash flows
        Rails.logger.debug "#########BUYS#########"
        portfolio_investments.filter { |pi| pi.quantity.positive? }.each do |buy|
          cf << Xirr::Transaction.new(-1 * buy.amount_cents, date: buy.investment_date, notes: "Buy #{buy.portfolio_company_name} #{buy.quantity}")
        end

        Rails.logger.debug "#########SELLS#########"
        # Get the sell cash flows
        portfolio_investments.filter { |pi| pi.quantity.negative? }.each do |sell|
          cf << Xirr::Transaction.new(sell.amount_cents, date: sell.investment_date, notes: "Sell #{sell.portfolio_company_name} #{sell.quantity}")
        end

        # Get the FMV for this specific portfolio_company
        fmv_val = fmv_on_date(portfolio_company_id).round(4)
        cf << Xirr::Transaction.new(fmv_val, date: @end_date, notes: "FMV portfolio_company_id: #{portfolio_company_id}") if fmv_val != 0

        Rails.logger.debug { "fmv = #{fmv_val}" }
        # Calculate and store the xirr

        lxirr = XirrApi.new.xirr(cf, "portfolio_company_irr:#{portfolio_company_id}")
        xirr_val = lxirr ? (lxirr * 100).round(2) : 0
        Rails.logger.debug { "xirr = #{xirr_val}" }

        cash_flows = return_cash_flows ? cf : nil
        @portfolio_companies_map[portfolio_company_id] = { name: portfolio_investments[0].portfolio_company_name,
                                                           xirr: xirr_val, cash_flows: }
        Rails.logger.debug xirr
      end

    end

    @portfolio_companies_map
  end

  def portfolio_company_cost_to_value
    # @fund.portfolio_investments.where(investment_date: ..@end_date).group_by(&:portfolio_company_id)
    #      .each do |portfolio_company_id, portfolio_investments|
    @portfolio_companies_map ||= {}

    @portfolio_company_cost_to_value ||= @fund.portfolio_investments.select { |pi| pi.Pool? && pi.investment_date <= @end_date }.sort_by(&:investment_date).group_by(&:portfolio_company_id).each do |portfolio_company_id, portfolio_investments|
      bought_amount = portfolio_investments.filter { |pi| pi.quantity.positive? }.sum(&:amount_cents)
      sold_amount = portfolio_investments.filter { |pi| pi.quantity.negative? }.sum(&:amount_cents)
      fmv = fmv_on_date(portfolio_company_id)

      @portfolio_companies_map[portfolio_company_id] =
        { name: portfolio_investments[0].portfolio_company_name,
          value_to_cost: (sold_amount + fmv) / bought_amount }
    end

    @portfolio_companies_map
  end

  def fmv_on_date(portfolio_company_id = nil)
    total_fmv_on_end_date_cents = 0
    # portfolio_investments = @fund.portfolio_investments.pool.where(investment_date: ..@end_date)
    portfolio_investments = @fund.portfolio_investments.select { |pi| pi.Pool? && pi.investment_date <= @end_date }

    # portfolio_investments = portfolio_investments.where(portfolio_company_id:) if portfolio_company_id
    portfolio_investments = portfolio_investments.select { |pi| pi.portfolio_company_id == portfolio_company_id } if portfolio_company_id

    Rails.logger.debug portfolio_investments

    # portfolio_investments.group(:portfolio_company_id, :category, :sub_category).sum(:quantity).each do |k, quantity|
    portfolio_investments.group_by { |pi| [pi.portfolio_company_id, pi.category, pi.sub_category] }.transform_values { |pis| pis.inject(0) { |sum, pi| sum + pi.quantity } }.each do |k, quantity|
      # Get the valuation as of the end date
      portfolio_company_id = k[0]
      category = k[1]
      sub_category = k[2]
      valuation = Valuation.where(owner_id: portfolio_company_id, owner_type: "Investor", category:,
                                  sub_category:, valuation_date: ..@end_date).order(valuation_date: :asc).last

      # We cannot proceed without a valid valuation
      raise "No valuation found for #{Investor.find(portfolio_company_id).investor_name} prior to date #{@end_date}" unless valuation

      # Get the fmv for this portfolio_company on the @end_date
      fmv_on_end_date_cents = quantity * valuation.per_share_value_cents
      # Aggregate the fmv across the fun
      total_fmv_on_end_date_cents += fmv_on_end_date_cents
    end
    total_fmv_on_end_date_cents
  end

  # Calculate the IRR for the fund
  # net_irr: true/false - if true, then the IRR is calculated net of Estimated Carry
  # return_cash_flows: true/false - if true, then the cash flows used in computation are returned
  # adjustment_cash: amount to be added to the cash flows, used specifically for scenarios. see PortfolioScenarioJob
  def xirr(net_irr: false, return_cash_flows: false, adjustment_cash: 0)
    cf = Xirr::Cashflow.new

    @fund.capital_remittance_payments.includes(:capital_remittance).where("capital_remittance_payments.payment_date <= ?", @end_date).each do |cr|
      cf << Xirr::Transaction.new(-1 * cr.amount_cents, date: cr.payment_date, notes: "#{cr.capital_remittance.investor_name} Remittance #{cr.id} ")
    end

    @fund.capital_distribution_payments.includes(:investor).where("capital_distribution_payments.payment_date <= ?", @end_date).each do |cdp|
      cf << Xirr::Transaction.new(cdp.amount_cents, date: cdp.payment_date, notes: "#{cdp.investor.investor_name} Distribution #{cdp.id}")
    end

    cf << Xirr::Transaction.new(fmv_on_date, date: @end_date, notes: "FMV") if fmv_on_date != 0
    cf << Xirr::Transaction.new(cash_in_hand_cents, date: @end_date, notes: "Cash in Hand") if cash_in_hand_cents != 0
    cf << Xirr::Transaction.new(net_current_assets_cents, date: @end_date, notes: "Net Current Assets") if net_current_assets_cents != 0

    cf << Xirr::Transaction.new(estimated_carry_cents, date: @end_date, notes: "Estimated carry") if net_irr
    cf << Xirr::Transaction.new(adjustment_cash, date: @end_date, notes: "Adjustment Cash") if adjustment_cash != 0

    Rails.logger.debug { "fund.xirr cf: #{cf}" }
    cf.each do |cash_flow|
      Rails.logger.debug "#{cash_flow.date}, #{cash_flow.amount}, #{cash_flow.notes}"
    end

    lxirr = XirrApi.new.xirr(cf, "xirr_#{@fund.id}_#{@end_date}") || 0
    Rails.logger.debug { "fund.xirr irr: #{lxirr}" }
    if return_cash_flows
      [(lxirr * 100).round(2), cf]
    else
      (lxirr * 100).round(2)
    end
  end

  def sample_xirr(count)
    cf = Xirr::Cashflow.new
    (1..count).each do |_i|
      cf << Xirr::Transaction.new(-1 * rand(1..10) * 1_000_000, date: Time.zone.today - rand(1..10).years - rand(1.12).months - rand(1..365).days)

      cf << Xirr::Transaction.new(rand(1..10) * 1_000_000, date: Time.zone.today - rand(1..10).years - rand(1.12).months - rand(1..365).days)
    end

    Rails.logger.debug cf

    XirrApi.new.xirr(cf, "sample_xirr")
  end
end
