class FundRatiosScenarioJob < ApplicationJob
  include Rails.application.routes.url_helpers
  include ApplicationHelper

  queue_as :low
  sidekiq_options retry: 1

  # This is used to generate fund ratios for a scenario
  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  # fund_id is the fund id where the ratios will be stored, we cannot make this optional as the policy framework needs this
  # fund_ids and portfolio_company_ids are optional
  # fund_ids: [1,2,3]
  # portfolio_company_ids: [4,5,6]
  # end_date: "2023-10-01"
  # user_id: 1
  # scenario: "Scenario A"
  def perform(fund_id, scenario, end_date, user_id, fund_ids: nil, portfolio_company_ids: nil, currency: nil, type: "cross-fund")
    # Use the first fund_id from fund_ids if fund_id is not provided
    fund_id ||= fund_ids[0] if fund_ids.present?

    # Raise an error and notify the user if no fund_id is specified
    msg = "No fund specified to generate Fund Ratios"
    if fund_id.nil?
      send_notification(msg, user_id, level: "danger")
      raise ArgumentError(msg)
    end

    # Initialize instance variables for the job
    @fund_id = fund_id
    @fund = Fund.find(fund_id) # Find the primary fund

    @scenario = scenario # Scenario for which ratios are calculated
    @end_date = end_date # End date for the calculations
    @funds = Fund.where(id: fund_ids) if fund_ids.present? # Optional list of funds
    @fund_ids = fund_ids # Store the fund IDs

    @portfolio_companies = Investor.where(id: portfolio_company_ids) if portfolio_company_ids.present? # Optional list of portfolio companies
    @portfolio_company_ids = portfolio_company_ids # Store the portfolio company IDs

    @user = User.find(user_id) # User initiating the job
    @currency ||= @user.entity.currency # Default currency based on the user's entity

    # Use Chewy's sidekiq strategy for Elasticsearch indexing
    Chewy.strategy(:sidekiq) do
      if type == "cross-fund"
        # Perform fund ratio calculations
        calc_fund_ratios
      elsif type == "cross-portfolio"
        # Perform portfolio company ratio calculations
        calc_portfolio_company_ratios
      else
        raise ArgumentError("Invalid type specified: #{type}")
      end

      filters = [
        [scenario.to_s, 'View Generated Ratios'],
        ['', 'View All Ratios']
      ]

      links_html = filters.map do |scenario, label|
        query_params = ransack_query_params_multiple([[:scenario, :eq, scenario]])
        ActionController::Base.helpers.link_to(label, fund_ratios_path(fund_id: fund_id, filter: true, q: query_params), class: 'mb-1 badge  bg-primary-subtle text-primary', target: '_blank', rel: 'noopener')
      end.join

      # Notify the user upon successful completion
      notify("#{scenario} ratio calculations are now complete.<br> #{links_html}", user_id)
    rescue StandardError => e
      # Notify the user in case of an error and re-raise the exception
      notify("Error in fund ratios: #{e.message}", user_id, level: "danger")
      raise e
    end
  end

  def calc_fund_ratios
    owner = @user
    # Blow off prev fund ratio calcs for this scenario / date
    FundRatio.where(scenario: @scenario, end_date: @end_date).delete_all

    calc = FundRatioMultiFundCalcs.new(@scenario, @end_date, @user.entity, funds: @funds, currency: @currency)

    # Create the ratios
    xirr, cash_flows = calc.xirr(return_cash_flows: false)
    FundRatio.create!(fund: @fund, owner:, entity_id: owner.entity_id, end_date: @end_date, name: "XIRR", value: xirr, cash_flows:, display_value: "#{xirr} %", scenario: @scenario)

    value = calc.gross_portfolio_irr
    display_value = "#{value} %"
    FundRatio.create!(fund: @fund, owner:, entity_id: owner.entity_id, end_date: @end_date, name: "Gross Portfolio IRR", value:, display_value:, scenario: @scenario)
  end

  def calc_portfolio_company_ratios
    owner = @user
    # Blow off prev fund ratio calcs for this scenario / date
    FundRatio.where(scenario: @scenario, end_date: @end_date).delete_all

    calc = FundRatioMultiFundCalcs.new(@scenario, @end_date, @user.entity, funds: @funds, portfolio_companies: @portfolio_companies, currency: @currency)

    value = calc.gross_portfolio_irr
    display_value = "#{value} %"
    FundRatio.create!(fund: @fund, owner:, entity_id: @fund.entity_id, end_date: @end_date, name: "Gross Portfolio IRR", value:, display_value:, scenario: @scenario)

    # Compute the portfolio_company_ratios
    calc.portfolio_company_irr(return_cash_flows: false).each do |portfolio_company_id, values|
      FundRatio.create!(owner_id: portfolio_company_id, owner_type: "Investor", entity_id: @fund.entity_id, fund: @fund, end_date: @end_date, name: "IRR", value: values[:xirr], display_value: "#{values[:xirr]} %", scenario: @scenario)
    end

    # Compute the portfolio_company_ratios
    calc.portfolio_company_metrics.each do |portfolio_company_id, values|
      FundRatio.create!(owner_id: portfolio_company_id, owner_type: "Investor", entity_id: @fund.entity_id, fund: @fund, end_date: @end_date, name: "Value To Cost", value: values[:value_to_cost], display_value: "#{values[:value_to_cost]&.round(2)} x")

      FundRatio.create!(owner_id: portfolio_company_id, owner_type: "Investor", entity_id: @fund.entity_id, fund: @fund, end_date: @end_date, name: "MOIC", value: values[:moic], display_value: "#{values[:moic]&.round(2)} x", scenario: @scenario)
    end
  end

  def notify(message, user_id, level: "success")
    UserAlert.new(user_id:, message:, level:).broadcast
  end
end
