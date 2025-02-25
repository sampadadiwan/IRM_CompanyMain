class FundPortfolioCalcs < FundRatioCalcs
  def initialize(fund, end_date)
    @fund = fund
    @end_date = end_date
    super()
  end

  def total_investment_costs_cents
    ticc = 0
    @fund.aggregate_portfolio_investments.each do |api|
      api_as_of = api.as_of(@end_date)
      ticc += api_as_of.cost_of_remaining_cents
    end
    ticc
  end

  def fmv_cents
    @fmv_cents ||= fmv_on_date
  end

  def total_investment_sold_cents
    @total_investment_sold_cents ||= PortfolioInvestment.total_investment_sold_cents(@fund, @end_date)
  end

  def distribution_cents
    @distribution_cents ||= @fund.capital_distribution_payments.completed.where(payment_date: ..@end_date).sum(:gross_payable_cents) -
                            @fund.capital_distribution_payments.completed.where(payment_date: ..@end_date).sum(:reinvestment_with_fees_cents)
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
    if collected_cents.positive? # ? (fmv_cents / collected_cents).round(2) : 0
      ((fmv_cents + net_current_assets_cents + cash_in_hand_cents) / collected_cents)
    else
      0
    end
  end

  def tvpi
    dpi + rvpi
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
      cf = XirrCashflow.new

      # Get the buy cash flows
      buy_pis = @fund.portfolio_investments.buys.before(@end_date)
      buy_pis.find_each do |buy|
        cf << XirrTransaction.new(-1 * buy.amount_cents, date: buy.investment_date, notes: "Bought Amount") if buy.amount_cents.positive?
      end

      # Adjust StockConversion - if the PI has been converted, remove the old PI from the cashflows
      Rails.logger.debug "#########StockConversion#########"
      @fund.stock_conversions.where(conversion_date: ..@end_date).find_each do |sc|
        quantity = sc.from_quantity
        pi = sc.from_portfolio_investment
        cf << XirrTransaction.new(quantity * pi.cost_cents, date: pi.investment_date, notes: "StockConversion #{pi.portfolio_company_name} #{quantity}")
      end

      # Get the sell cash flows
      @fund.portfolio_investments.sells.where(investment_date: ..@end_date).find_each do |sell|
        cf << XirrTransaction.new(sell.amount_cents, date: sell.investment_date, notes: "Sold Amount") if sell.amount_cents.positive?
      end

      # Get the FMV
      cf << XirrTransaction.new(fmv_on_date, date: @end_date, notes: "FMV on Date") if fmv_on_date.positive?

      # loop over all apis
      @fund.aggregate_portfolio_investments.each do |api|
        portfolio_cashflows = api.portfolio_cashflows.actual.where(payment_date: ..@end_date)
        portfolio_cashflows.each do |pcf|
          cf << XirrTransaction.new(pcf.amount_cents, date: pcf.payment_date, notes: "Portfolio Income") if pcf.amount_cents.positive?
        end
      end

      cf.each { |cash_flow| Rails.logger.debug "#{cash_flow.date}, #{cash_flow.amount}, #{cash_flow.notes}" }

      lxirr = XirrApi.new.xirr(cf, "gross_portfolio_irr")
      # lxirr ? (lxirr * 100).round(2) : 0
      (lxirr * 100).round(2)
    end
  end

  # rubocop:disable Metrics/MethodLength
  # rubocop:disable Metrics/BlockLength
  # Compute the XIRR for each portfolio company
  def portfolio_company_irr(return_cash_flows: false, scenarios: nil)
    @portfolio_company_irr_map ||= {}

    if @portfolio_company_irr_map.empty?
      # Get all the Portfolio companies
      @fund.portfolio_investments.pluck(:portfolio_company_id).uniq.each do |portfolio_company_id| # rubocop:disable Metrics/BlockLength
        portfolio_company = Investor.find(portfolio_company_id)
        # Get all the portfolio investments for this portfolio company before the end date
        portfolio_investments = @fund.portfolio_investments.where(portfolio_company_id:).before(@end_date)

        cf = XirrCashflow.new

        # Get the buy cash flows
        Rails.logger.debug "#########BUYS#########"
        portfolio_investments.filter { |pi| pi.quantity.positive? }.each do |buy|
          cf << XirrTransaction.new(-1 * buy.amount_cents, date: buy.investment_date, notes: "Buy #{buy.portfolio_company_name} #{buy.quantity}")
        end

        # Adjust StockConversion - if the PI has been converted, remove the old PI from the cashflows
        Rails.logger.debug "#########StockConversion#########"
        @fund.stock_conversions.where(conversion_date: ..@end_date, from_portfolio_investment_id: portfolio_investments.pluck(:id)).find_each do |sc|
          quantity = sc.from_quantity
          pi = sc.from_portfolio_investment
          cf << XirrTransaction.new(quantity * pi.cost_cents, date: pi.investment_date, notes: "StockConversion #{pi.portfolio_company_name} #{quantity}")
        end

        Rails.logger.debug "#########SELLS#########"
        # Get the sell cash flows
        portfolio_investments.filter { |pi| pi.quantity.negative? }.each do |sell|
          cf << XirrTransaction.new(sell.amount_cents, date: sell.investment_date, notes: "Sell #{sell.portfolio_company_name} #{sell.quantity}")
        end

        Rails.logger.debug "#########FMV & Portfolio CF#########"

        # Get the FMV for this specific portfolio_company
        @fund.aggregate_portfolio_investments.where(portfolio_company_id:).find_each do |api|
          # Get the portfolio income cash flows
          portfolio_cashflows = api.portfolio_cashflows.actual.where(portfolio_company_id:, payment_date: ..@end_date)
          portfolio_cashflows.each do |pcf|
            cf << XirrTransaction.new(pcf.amount_cents, date: pcf.payment_date, notes: "Portfolio Income") if pcf.amount_cents.positive?
          end

          # Get the FMV for this specific portfolio_company
          fmv_val = fmv_on_date(api, scenarios:).round(4)
          cf << XirrTransaction.new(fmv_val, date: @end_date, notes: "FMV api: #{api}") if fmv_val != 0
          Rails.logger.debug { "#{api.id} fmv = #{fmv_val}" }
        end

        # Calculate and store the xirr
        lxirr = XirrApi.new.xirr(cf, "portfolio_company_irr:#{portfolio_company_id}")
        xirr_val = lxirr ? (lxirr * 100).round(2) : 0
        Rails.logger.debug { "#{portfolio_company_id} xirr = #{xirr_val}" }

        cash_flows = return_cash_flows ? cf : nil
        @portfolio_company_irr_map[portfolio_company_id] = { name: portfolio_company.investor_name, xirr: xirr_val, cash_flows: }
      end

    end

    @portfolio_company_irr_map
  end
  # rubocop:enable Metrics/MethodLength
  # rubocop:enable Metrics/BlockLength

  def portfolio_company_metrics
    @portfolio_company_metrics_map ||= {}

    @fund.aggregate_portfolio_investments.pluck(:portfolio_company_id).uniq.each do |portfolio_company_id|
      portfolio_company = Investor.find(portfolio_company_id)

      bought_amount = 0
      total_fmv = 0
      total_sold = 0

      @fund.aggregate_portfolio_investments.where(portfolio_company_id:).find_each do |api|
        api_as_of = api.as_of(@end_date)
        total_fmv += api_as_of.fmv
        bought_amount += api_as_of.bought_amount
        total_sold += api_as_of.sold_amount

        Rails.logger.debug { "API: #{api.id}, FMV: #{api_as_of.fmv}, Bought: #{api_as_of.bought_amount}, Sold: #{api_as_of.sold_amount}" }
      end

      Rails.logger.debug { "Portfolio Company: #{portfolio_company_id}, Total FMV: #{total_fmv}, Total Sold: #{total_sold}, Bought Amount: #{bought_amount}" }

      next unless bought_amount.positive?

      value_to_cost = total_fmv / bought_amount.to_f
      moic = (total_fmv + total_sold) / bought_amount.to_f

      @portfolio_company_metrics_map[portfolio_company_id] = {
        name: portfolio_company.investor_name,
        value_to_cost: value_to_cost,
        moic: moic
      }
    end

    @portfolio_company_metrics_map
  end

  # Compute the XIRR for each API
  def api_irr(return_cash_flows: false, scenarios: nil)
    @api_irr_map ||= {}

    if @api_irr_map.empty?

      @fund.aggregate_portfolio_investments.each do |api|
        api.portfolio_company_id

        portfolio_investments = api.portfolio_investments.before(@end_date)
        # If there are no portfolio investments for this API, then skip
        next if portfolio_investments.blank?

        cf = XirrCashflow.new

        # Get the buy cash flows
        portfolio_investments.filter { |pi| pi.quantity.positive? }.each do |buy|
          cf << XirrTransaction.new(-1 * buy.amount_cents, date: buy.investment_date, notes: "Buy #{buy.portfolio_company_name} #{buy.quantity}")
        end

        # Adjust StockConversion - if the PI has been converted, remove the old PI from the cashflows
        @fund.stock_conversions.where(conversion_date: ..@end_date, from_portfolio_investment_id: portfolio_investments.pluck(:id)).find_each do |sc|
          quantity = sc.from_quantity
          pi = sc.from_portfolio_investment
          cf << XirrTransaction.new(quantity * pi.cost_cents, date: pi.investment_date, notes: "StockConversion #{pi.portfolio_company_name} #{quantity}")
        end

        # Get the sell cash flows
        portfolio_investments.filter { |pi| pi.quantity.negative? }.each do |sell|
          cf << XirrTransaction.new(sell.amount_cents, date: sell.investment_date, notes: "Sell #{sell.portfolio_company_name} #{sell.quantity}")
        end

        # Get the portfolio income cash flows
        portfolio_cashflows = api.portfolio_cashflows.actual.where(payment_date: ..@end_date)
        portfolio_cashflows.each do |pcf|
          cf << XirrTransaction.new(pcf.amount_cents, date: pcf.payment_date, notes: "Portfolio Income") if pcf.amount_cents.positive?
        end

        # Get the FMV for this specific portfolio_company
        fmv_val = fmv_on_date(api, scenarios:).round(4)
        cf << XirrTransaction.new(fmv_val, date: @end_date, notes: "FMV api: #{api}") if fmv_val != 0

        Rails.logger.debug { "#{api.id} fmv = #{fmv_val}" }
        # Calculate and store the xirr

        lxirr = XirrApi.new.xirr(cf, "api_irr:#{api.id}")
        xirr_val = lxirr ? (lxirr * 100).round(2) : 0
        Rails.logger.debug { "#{api.id} xirr = #{xirr_val}" }

        cash_flows = return_cash_flows ? cf : nil
        @api_irr_map[api.id] = { name: api.to_s, xirr: xirr_val, cash_flows: }
      end

    end

    Rails.logger.debug @api_irr_map
    @api_irr_map
  end

  def api_cost_to_value
    @api_cost_map ||= {}

    @fund.aggregate_portfolio_investments.each do |api|
      api.portfolio_investments.where(investment_date: ..@end_date)

      api_as_of = api.as_of(@end_date)
      bought_amount = api_as_of.bought_amount
      fmv = api_as_of.fmv

      @api_cost_map[api.id] = { name: api.to_s, value_to_cost: (fmv / bought_amount) } if bought_amount.positive?
    end

    @api_cost_map
  end

  def fmv_on_date(aggregate_portfolio_investment = nil, scenarios: nil)
    total_fmv_on_end_date_cents = 0

    apis = aggregate_portfolio_investment ? [aggregate_portfolio_investment] : @fund.aggregate_portfolio_investments

    Rails.logger.debug apis

    apis.each do |api|
      fmv_on_end_date_cents = api.fmv_on_date(@end_date)

      # Applied only if there is a scenario
      fmv_on_end_date_cents = (fmv_on_end_date_cents * (1 + (scenarios[api.id.to_s]["percentage_change"].to_f / 100))).round(4) if api && scenarios && scenarios[api.id.to_s]["percentage_change"].present?

      Rails.logger.debug { "FMV on End Date: #{fmv_on_end_date_cents}, API: #{api.id}" }
      # Aggregate the fmv across the fun
      total_fmv_on_end_date_cents += fmv_on_end_date_cents
    end

    total_fmv_on_end_date_cents
  end

  # Calculate the IRR for the fund
  # net_irr: true/false - if true, then the IRR is calculated net of Estimated Carry
  # return_cash_flows: true/false - if true, then the cash flows used in computation are returned
  # adjustment_cash: amount to be added to the cash flows, used specifically for scenarios. see PortfolioScenarioJob
  def xirr(net_irr: false, return_cash_flows: false, adjustment_cash: 0, scenarios: nil, use_tracking_currency: false)
    super(entity: @fund, net_irr:, return_cash_flows:, adjustment_cash:, scenarios:, use_tracking_currency:)
  end

  def sample_xirr(count)
    cf = XirrCashflow.new
    (1..count).each do |_i|
      cf << XirrTransaction.new(-1 * rand(1..10) * 1_000_000, date: Time.zone.today - rand(1..10).years - rand(1.12).months - rand(1..365).days)

      cf << XirrTransaction.new(rand(1..10) * 1_000_000, date: Time.zone.today - rand(1..10).years - rand(1.12).months - rand(1..365).days)
    end

    Rails.logger.debug cf

    XirrApi.new.xirr(cf, "sample_xirr")
  end
end
