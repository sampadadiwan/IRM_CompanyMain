class PortfolioScenarioJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: 1

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(id, user_id, return_cash_flows: false)
    portfolio_scenario = PortfolioScenario.find(id)

    fund = portfolio_scenario.fund
    synthetic_investments = portfolio_scenario.scenario_investments.map(&:to_portfolio_investment)

    # These synthetic_investments should cause the cash in hand to change, so lets compute that
    adjustment_cash = synthetic_investments.inject(0) { |sum, investment| sum + investment.amount_cents }

    # This is the last transaction date for the scenario_investments
    last_transaction_date = portfolio_scenario.scenario_investments.order(transaction_date: :desc).first&.transaction_date || Time.zone.today

    fpc = FundPortfolioCalcs.new(fund, last_transaction_date)
    # Get the xirr and moic for the fund including the synthetic investments (via  adjustment cash)
    xirr, xirr_cash_flows = fpc.xirr(adjustment_cash:, return_cash_flows:)
    moic, moic_cash_flows = fpc.moic(synthetic_investments:, return_cash_flows:)
    moic = moic.round(2).to_f
    calculations = { xirr: xirr, moic: moic }
    calculations[:xirr_cash_flows] = xirr_cash_flows&.to_json if return_cash_flows
    calculations[:moic_cash_flows] = moic_cash_flows&.to_json if return_cash_flows

    # Get the irr and moic for each portfolio company including the synthetic investments
    portfolio_company_irr_hash = fpc.portfolio_company_irr(return_cash_flows:, synthetic_investments: synthetic_investments)

    calculations[:portfolio_company_metrics] = portfolio_company_irr_hash.to_json

    portfolio_scenario.calculations = calculations

    portfolio_scenario.save

    UserAlert.new(user_id:, message: "Portfolio Scenario: #{portfolio_scenario.name} has been run successfully.", level: "success").broadcast
  rescue StandardError => e
    UserAlert.new(user_id:, message: "Portfolio Scenario: #{portfolio_scenario.name} - Error: #{e.message}", level: "danger").broadcast
    raise e
  end
end
