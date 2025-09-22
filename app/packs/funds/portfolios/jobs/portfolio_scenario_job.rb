class PortfolioScenarioJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: 1

  # Main job entry point.
  # Calculates scenario metrics (XIRR, MOIC, portfolio company IRR) for a PortfolioScenario.
  # Handles both default and tracking currencies, and broadcasts success/error alerts.
  def perform(id, user_id, return_cash_flows: false, cashflows_currency: "default")
    portfolio_scenario = PortfolioScenario.find(id)

    fund = portfolio_scenario.fund
    use_tracking_currency = fund.has_tracking_currency?
    synthetic_investments = portfolio_scenario.scenario_investments.map(&:to_portfolio_investment)

    # Sum the amounts of synthetic investments to adjust cash in hand.
    adjustment_cash = synthetic_investments.inject(0) { |sum, investment| sum + investment.amount_cents }

    # Get the latest transaction date from scenario investments, or use today if none exist.
    last_transaction_date = portfolio_scenario.scenario_investments.order(transaction_date: :desc).first&.transaction_date || Time.zone.today

    fpc = FundPortfolioCalcs.new(fund, last_transaction_date)
    # Calculate XIRR and MOIC for the fund, including synthetic investments.
    xirr, xirr_cash_flows = fpc.xirr(adjustment_cash:, return_cash_flows:)
    moic, moic_cash_flows = fpc.moic(synthetic_investments:, return_cash_flows:)
    moic = moic.round(2).to_f
    calculations = { xirr: xirr, moic: moic }
    calculations[:xirr_cash_flows] = xirr_cash_flows&.to_json if return_cash_flows
    calculations[:moic_cash_flows] = moic_cash_flows&.to_json if return_cash_flows
    calculations[:currency] = fund.currency

    # Calculate IRR and MOIC for each portfolio company, including synthetic investments.
    portfolio_company_irr_hash = fpc.portfolio_company_irr(return_cash_flows:, synthetic_investments: synthetic_investments)
    fpc.portfolio_company_irr_map = {}

    # If fund has tracking currency, add metrics in tracking currency as well.
    if use_tracking_currency
      portfolio_company_irr_hash_tracking_curr = add_tracking_currency_data(adjustment_cash:, return_cash_flows:, cashflows_currency:, calculations:, fpc:, fund:, synthetic_investments:)

      # Combine default and tracking currency metrics for each portfolio company.
      combined_hash = combine_default_and_tracking(portfolio_company_irr_hash, portfolio_company_irr_hash_tracking_curr, cashflows_currency, fund.tracking_currency)
      calculations[:portfolio_company_metrics] = combined_hash.to_json
    else
      calculations[:portfolio_company_metrics] = portfolio_company_irr_hash.to_json
    end

    portfolio_scenario.calculations = calculations

    portfolio_scenario.save

    # Broadcast success alert to user.
    UserAlert.new(user_id:, message: "Portfolio Scenario: #{portfolio_scenario.name} has been run successfully.", level: "success").broadcast
  rescue StandardError => e
    # Broadcast error alert to user and re-raise exception.
    UserAlert.new(user_id:, message: "Portfolio Scenario: #{portfolio_scenario.name} - Error: #{e.message}", level: "danger").broadcast
    raise e
  end

  # Adds tracking currency metrics to calculations hash.
  # Returns portfolio company IRR hash in tracking currency.
  def add_tracking_currency_data(adjustment_cash:, return_cash_flows:, cashflows_currency:, calculations:, fpc:, fund:, synthetic_investments:) # rubocop:disable Metrics/ParameterLists
    tracking_currency = fund.tracking_currency
    xirr_tracking_curr, xirr_cash_flows_tracking_curr = fpc.xirr(adjustment_cash:, return_cash_flows:, use_tracking_currency: true)
    moic_tracking_curr, moic_cash_flows_tracking_curr = fpc.moic(synthetic_investments:, return_cash_flows:, use_tracking_currency: true)
    moic_tracking_curr = moic_tracking_curr.round(2).to_f

    calculations[:xirr_tracking_currency] = xirr_tracking_curr
    calculations[:moic_tracking_currency] = moic_tracking_curr
    # Only include tracking currency cash flows if requested.
    calculations[:xirr_cash_flows] = xirr_cash_flows_tracking_curr&.to_json if return_cash_flows && cashflows_currency.downcase == "tracking"
    calculations[:moic_cash_flows] = moic_cash_flows_tracking_curr&.to_json if return_cash_flows && cashflows_currency.downcase == "tracking"
    calculations[:tracking_currency] = tracking_currency

    # Return portfolio company IRR hash in tracking currency.
    fpc.portfolio_company_irr(return_cash_flows:, synthetic_investments: synthetic_investments, use_tracking_currency: true)
  end

  # Combines default and tracking currency metrics for each portfolio company.
  # Selects cash flows based on requested currency.
  def combine_default_and_tracking(base_data, tracking_data, cashflows_currency, tracking_currency)
    (base_data.keys | tracking_data.keys).each_with_object({}) do |key, acc|
      base_row     = base_data[key]     || {}
      tracking_row = tracking_data[key] || {}

      cash_flows =
        if cashflows_currency.to_s.downcase == "tracking"
          tracking_row[:cash_flows] || base_row[:cash_flows]
        else
          base_row[:cash_flows] || tracking_row[:cash_flows]
        end

      acc[key] = {
        name: base_row[:name] || tracking_row[:name],
        xirr: base_row[:xirr],
        "xirr_#{tracking_currency}": tracking_row[:xirr],
        moic: base_row[:moic],
        "moic_#{tracking_currency}": tracking_row[:moic],
        cash_flows: cash_flows
      }
    end
  end
end
