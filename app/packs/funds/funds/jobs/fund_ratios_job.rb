class FundRatiosJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: 1

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(fund_id, capital_commitment_id, end_date, user_id, generate_for_commitments)
    fund, capital_commitment = _setup_job(fund_id, capital_commitment_id)

    Chewy.strategy(:sidekiq) do
      _calculate_and_touch(fund, capital_commitment, end_date)
      _generate_ratios_for_commitments(fund, end_date, user_id) if generate_for_commitments
      fund.update_latest_fund_ratios(end_date)
      _handle_success_notification(fund, user_id)
    rescue StandardError => e
      _handle_error_notification(e, user_id)
    end
  end

  private

  def _setup_job(fund_id, capital_commitment_id)
    fund = Fund.find(fund_id)
    capital_commitment = capital_commitment_id ? CapitalCommitment.find(capital_commitment_id) : nil
    [fund, capital_commitment]
  end

  def _calculate_and_touch(fund, capital_commitment, end_date)
    calc_fund_ratios(fund, capital_commitment, end_date)
    capital_commitment&.touch
    fund.touch
  end

  def _generate_ratios_for_commitments(fund, end_date, user_id)
    fund.capital_commitments.each do |capital_commitment|
      calc_fund_ratios(fund, capital_commitment, end_date)
      notify("Folio #{capital_commitment.folio_id} calculations are now complete.", user_id)
    rescue StandardError => e
      notify("Error in fund ratios: #{e.message}", user_id, level: "danger")
      raise e
    end
  end

  def _handle_success_notification(fund, user_id)
    notify("#{fund.name} fund ratio calculations are now complete. Please refresh the page.", user_id)
  end

  def _handle_error_notification(error, user_id)
    notify("Error in fund ratios: #{error.message}", user_id, level: "danger")
    raise error
  end

  def calc_fund_ratios(fund, capital_commitment, end_date)
    owner = capital_commitment || fund
    _delete_previous_fund_ratios(fund, capital_commitment, end_date)
    calc = _initialize_calculator(fund, capital_commitment, end_date)

    _create_xirr_ratios(calc, owner, fund, capital_commitment, end_date)
    _create_rvpi_ratio(calc, owner, fund, capital_commitment, end_date)
    _create_dpi_ratio(calc, owner, fund, capital_commitment, end_date)
    _create_tvpi_ratio(calc, owner, fund, capital_commitment, end_date)

    calc_only_fund(calc, fund, capital_commitment, end_date, owner) unless capital_commitment
  end

  def _delete_previous_fund_ratios(fund, capital_commitment, end_date)
    FundRatio.where(fund:, capital_commitment:, end_date:).delete_all
  end

  def _initialize_calculator(fund, capital_commitment, end_date)
    capital_commitment ? CapitalCommitmentCalcs.new(capital_commitment, end_date) : FundPortfolioCalcs.new(fund, end_date)
  end

  def _create_xirr_ratios(calc, owner, fund, capital_commitment, end_date)
    xirr, cash_flows = calc.xirr(return_cash_flows: false)
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "XIRR", value: xirr, cash_flows:, display_value: "#{xirr} %")

    if fund.has_tracking_currency?
      tracking_xirr, cash_flows = calc.xirr(return_cash_flows: false, use_tracking_currency: true)
      FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "XIRR (#{fund.tracking_currency})", value: tracking_xirr, cash_flows:, display_value: "#{tracking_xirr} %")
    end
  end

  def _create_rvpi_ratio(calc, owner, fund, capital_commitment, end_date)
    value = calc.rvpi
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "RVPI", value:, display_value:)
  end

  def _create_dpi_ratio(calc, owner, fund, capital_commitment, end_date)
    value = calc.dpi
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "DPI", value:, display_value:)
  end

  def _create_tvpi_ratio(calc, owner, fund, capital_commitment, end_date)
    value = calc.tvpi
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "TVPI", value:, display_value:)
  end

  def calc_only_fund(calc, fund, capital_commitment, end_date, owner)
    _create_portfolio_value_to_cost_ratio(calc, owner, fund, capital_commitment, end_date)
    _create_paid_in_to_committed_capital_ratio(calc, owner, fund, capital_commitment, end_date)
    _create_portfolio_company_irr_ratios(calc, fund, capital_commitment, end_date)
    _create_api_irr_ratios(calc, fund, capital_commitment, end_date)
    _create_portfolio_company_moic_ratios(calc, fund, capital_commitment, end_date)
    _create_api_moic_ratios(calc, fund, capital_commitment, end_date)
    _create_gross_portfolio_irr_ratios(calc, owner, fund, capital_commitment, end_date)
  end

  def _create_portfolio_value_to_cost_ratio(calc, owner, fund, capital_commitment, end_date)
    value = calc.portfolio_value_to_cost
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "Portfolio Value to Cost", value:, display_value:)
  end

  def _create_paid_in_to_committed_capital_ratio(calc, owner, fund, capital_commitment, end_date)
    value = calc.paid_in_to_committed_capital
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "Paid In to Committed Capital", value:, display_value:)
  end

  def _create_portfolio_company_irr_ratios(calc, fund, capital_commitment, end_date)
    calc.portfolio_company_irr(return_cash_flows: false).each do |portfolio_company_id, values|
      FundRatio.create!(owner_id: portfolio_company_id, owner_type: "Investor", entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "IRR", value: values[:xirr], display_value: "#{values[:xirr]} %")
    end

    if fund.has_tracking_currency?
      calc.portfolio_company_irr(return_cash_flows: false, use_tracking_currency: true).each do |portfolio_company_id, values|
        FundRatio.create!(owner_id: portfolio_company_id, owner_type: "Investor", entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "IRR (#{fund.tracking_currency})", value: values[:xirr], display_value: "#{values[:xirr]} %")
      end
    end
  end

  def _create_api_irr_ratios(calc, fund, capital_commitment, end_date)
    calc.api_irr(return_cash_flows: false).each do |api_id, values|
      value = values[:xirr]
      cash_flows = values[:cash_flows]
      FundRatio.create!(owner_id: api_id, owner_type: "AggregatePortfolioInvestment", entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "IRR", value:, cash_flows:, display_value: "#{value} %")
    end

    if fund.has_tracking_currency?
      calc.api_irr(return_cash_flows: false, use_tracking_currency: true).each do |api_id, values|
        FundRatio.create!(owner_id: api_id, owner_type: "AggregatePortfolioInvestment", entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "IRR (#{fund.tracking_currency})", value: values[:xirr], display_value: "#{values[:xirr]} %")
      end
    end
  end

  def _create_portfolio_company_moic_ratios(calc, fund, capital_commitment, end_date)
    calc.portfolio_company_metrics.each do |portfolio_company_id, values|
      FundRatio.create!(owner_id: portfolio_company_id, owner_type: "Investor", entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "MOIC", value: values[:moic], display_value: "#{values[:moic]&.round(2)} x")
    end
  end

  def _create_api_moic_ratios(calc, fund, capital_commitment, end_date)
    calc.api_cost_to_value.each do |api_id, values|
      FundRatio.create!(owner_id: api_id, owner_type: "AggregatePortfolioInvestment", entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "MOIC", value: values[:moic], display_value: "#{values[:moic]&.round(2)} x")
    end
  end

  def _create_gross_portfolio_irr_ratios(calc, owner, fund, capital_commitment, end_date)
    value = calc.gross_portfolio_irr
    display_value = "#{value} %"
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "Gross Portfolio IRR", value:, display_value:)

    if fund.has_tracking_currency?
      value = calc.gross_portfolio_irr(use_tracking_currency: true)
      display_value = "#{value} %"
      FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "Gross Portfolio IRR (#{fund.tracking_currency})", value:, display_value:)
    end
  end

  def notify(message, user_id, level: "success")
    UserAlert.new(user_id:, message:, level:).broadcast
  end
end
