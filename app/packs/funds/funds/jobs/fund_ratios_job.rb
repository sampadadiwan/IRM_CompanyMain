class FundRatiosJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: 1

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(fund_id, capital_commitment_id, end_date, user_id, generate_for_commitments)
    fund = Fund.find(fund_id)
    capital_commitment = capital_commitment_id ? CapitalCommitment.find(capital_commitment_id) : nil

    Chewy.strategy(:sidekiq) do
      calc_fund_ratios(fund, capital_commitment, end_date)
      capital_commitment&.touch
      fund.touch

      if generate_for_commitments
        fund.capital_commitments.each do |capital_commitment|
          calc_fund_ratios(fund, capital_commitment, end_date)
          notify("Folio #{capital_commitment.folio_id} calculations are now complete.", user_id)
        rescue StandardError => e
          notify("Error in fund ratios: #{e.message}", user_id, level: "danger")
          raise e
        end
      end

      # Update the latest flag
      fund.update_latest_fund_ratios(end_date)

      # Notify the user
      notify("#{fund.name} fund ratio calculations are now complete. Please refresh the page.", user_id)
    rescue StandardError => e
      notify("Error in fund ratios: #{e.message}", user_id, level: "danger")
      raise e
    end
  end

  def calc_fund_ratios(fund, capital_commitment, end_date)
    owner = capital_commitment || fund
    # Blow off prev fund ratio calcs for this valuation
    FundRatio.where(fund:, capital_commitment:, end_date:).delete_all

    calc = capital_commitment ? CapitalCommitmentCalcs.new(capital_commitment, end_date) : FundPortfolioCalcs.new(fund, end_date)

    # Create the ratios
    xirr, cash_flows = calc.xirr(return_cash_flows: false)
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "XIRR", value: xirr, cash_flows:, display_value: "#{xirr} %")

    if fund.has_tracking_currency?
      tracking_xirr, cash_flows = calc.xirr(return_cash_flows: false, use_tracking_currency: true)
      FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "XIRR (#{fund.tracking_currency})", value: tracking_xirr, cash_flows:, display_value: "#{tracking_xirr} %")
    end

    # FundRatio.create!(owner: , entity_id: fund.entity_id, fund:, name: "Moic", value: calc.moic, display_value: calc.moic.to_s)

    value = calc.rvpi
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "RVPI", value:, display_value:)

    value = calc.dpi
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "DPI", value:, display_value:)

    value = calc.tvpi
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "TVPI", value:, display_value:)

    calc_only_fund(calc, fund, capital_commitment, end_date, owner) unless capital_commitment
  end

  def calc_only_fund(calc, fund, capital_commitment, end_date, owner)
    value = calc.fund_utilization
    display_value = value ? "#{value.round(2) * 100}%" : nil
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "Fund Utilization", value:, display_value:)

    value = calc.portfolio_value_to_cost
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "Portfolio Value to Cost", value:, display_value:)

    value = calc.paid_in_to_committed_capital
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "Paid In to Committed Capital", value:, display_value:)

    # Compute the portfolio_company_ratios
    calc.portfolio_company_irr(return_cash_flows: false).each do |portfolio_company_id, values|
      FundRatio.create!(owner_id: portfolio_company_id, owner_type: "Investor", entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "IRR", value: values[:xirr], display_value: "#{values[:xirr]} %")
    end

    calc.api_irr(return_cash_flows: false).each do |api_id, values|
      value = values[:xirr]
      cash_flows = values[:cash_flows]
      FundRatio.create!(owner_id: api_id, owner_type: "AggregatePortfolioInvestment", entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "IRR", value:, cash_flows:, display_value: "#{value} %")
    end

    # Compute the portfolio_company_ratios
    calc.portfolio_company_cost_to_value.each do |portfolio_company_id, values|
      FundRatio.create!(owner_id: portfolio_company_id, owner_type: "Investor", entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "Value To Cost", value: values[:value_to_cost], display_value: "#{values[:value_to_cost]&.round(2)} x")
    end

    calc.api_cost_to_value.each do |api_id, values|
      FundRatio.create!(owner_id: api_id, owner_type: "AggregatePortfolioInvestment", entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "Value To Cost", value: values[:value_to_cost], display_value: "#{values[:value_to_cost]&.round(2)} x")
    end

    value = calc.gross_portfolio_irr
    display_value = "#{value} %"
    FundRatio.create!(owner:, entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "Gross Portfolio IRR", value:, display_value:)
  end

  def notify(message, user_id, level: "success")
    UserAlert.new(user_id:, message:, level:).broadcast
  end
end
