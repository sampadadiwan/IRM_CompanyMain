class FundRatiosJob < ApplicationJob
  queue_as :low

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
          notify("Error in fund ratios: #{e.message}", user_id, level: "alert").broadcast
        end
      end

      # Notify the user
      notify("#{fund.name} fund ratio calculations are now complete. Please refresh the page.", user_id)
    end
  end

  def calc_fund_ratios(fund, capital_commitment, end_date)
    # Blow off prev fund ratio calcs for this valuation
    FundRatio.where(fund:, capital_commitment:, end_date:).delete_all

    calc = capital_commitment ? CapitalCommitmentCalcs.new(capital_commitment, end_date) : FundPortfolioCalcs.new(fund, end_date)

    # Create the ratios
    xirr = calc.xirr
    FundRatio.create!(entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "XIRR", value: xirr, display_value: "#{xirr} %")

    # FundRatio.create!(entity_id: fund.entity_id, fund:, name: "Moic", value: calc.moic, display_value: calc.moic.to_s)

    value = calc.rvpi
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create!(entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "RVPI", value:, display_value:)

    value = calc.dpi
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create!(entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "DPI", value:, display_value:)

    value = calc.tvpi
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create!(entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "TVPI", value:, display_value:)

    calc_only_fund(calc, fund, capital_commitment, end_date) unless capital_commitment
  end

  def calc_only_fund(calc, fund, capital_commitment, end_date)
    value = calc.fund_utilization
    display_value = value ? "#{value.round(2) * 100}%" : nil
    FundRatio.create!(entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "Fund Utilization", value:, display_value:)

    value = calc.portfolio_value_to_cost
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create!(entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "Portfolio Value to Cost", value:, display_value:)

    value = calc.paid_in_to_committed_capital
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create!(entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "Paid In to Committed Capital", value:, display_value:)

    # Compute the portfolio_company_ratios
    calc.portfolio_company_irr.each do |_portfolio_company_id, values|
      FundRatio.create!(entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "IRR: #{values[:name]}", value: values[:xirr], display_value: "#{values[:xirr]} %")
    end

    # Compute the portfolio_company_ratios
    calc.portfolio_company_cost_to_value.each do |_portfolio_company_id, values|
      FundRatio.create!(entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "Value To Cost: #{values[:name]}", value: values[:value_to_cost], display_value: "#{values[:value_to_cost].round(2)} x")
    end

    value = calc.gross_portfolio_irr
    display_value = "#{value} %"
    FundRatio.create!(entity_id: fund.entity_id, fund:, capital_commitment:, end_date:, name: "Gross Portfolio IRR", value:, display_value:)
  end

  def notify(message, user_id, level: "success")
    UserAlert.new(user_id:, message:, level:).broadcast
  end
end
