class PortfolioScenarioJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: 1

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(id, user_id, return_cash_flows: false)
    portfolio_scenario = PortfolioScenario.find(id)

    fund = portfolio_scenario.fund
    fund.portfolio_investments.to_a
    synthetic_investments = portfolio_scenario.scenario_investments.map(&:to_portfolio_investment)
    fund.portfolio_investments << synthetic_investments
    # These synthetic_investments should cause the cash in hand to change, so lets compute that
    adjustment_cash = synthetic_investments.inject(0) { |sum, investment| sum + investment.amount_cents }

    # This is the last transaction date for the scenario_investments
    last_transaction_date = portfolio_scenario.scenario_investments.order(transaction_date: :desc).first&.transaction_date || Time.zone.today

    fpc = FundPortfolioCalcs.new(fund, last_transaction_date)
    xirr, xirr_cash_flows = fpc.xirr(adjustment_cash:, return_cash_flows:)

    calculations = { xirr: }
    calculations[:xirr_cash_flows] = xirr_cash_flows&.to_json if return_cash_flows
    calculations[:portfolio_company_irr] = fpc.portfolio_company_irr(return_cash_flows:).values&.to_json

    portfolio_scenario.calculations = calculations

    portfolio_scenario.save

    UserAlert.new(user_id:, message: "Portfolio Scenario has been run successfully.", level: "success").broadcast
  rescue StandardError => e
    UserAlert.new(user_id:, message: "Portfolio Scenario Error: #{e.message}", level: "danger").broadcast
    raise e
  end
end
