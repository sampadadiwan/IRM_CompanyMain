class FundCalcJob < ApplicationJob
  queue_as :low

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(fund_id, user_id)
    Chewy.strategy(:sidekiq) do
      fund = Fund.find(fund_id)
      valuation = fund.valuations.order(valuation_date: :asc).last

      calc_ratios(fund, valuation)
      fund.touch

      # Notify the user
      notify(fund, user_id)
    end
  end

  def calc_ratios(fund, valuation)
    # Blow off prev fund ratio calcs for this valuation
    FundRatio.where(fund:, valuation:).delete_all

    calc = FundCalcs.new(fund, valuation)
    # Create the ratios
    xirr = calc.compute_xirr
    FundRatio.create(entity_id: fund.entity_id, fund:, valuation:, name: "Xirr", value: xirr, display_value: "#{xirr} %")
    FundRatio.create(entity_id: fund.entity_id, fund:, valuation:, name: "Moic", value: calc.compute_moic, display_value: calc.compute_moic.to_s)

    value = calc.compute_rvpi
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create(entity_id: fund.entity_id, fund:, valuation:, name: "Rvpi", value:, display_value:)

    value = calc.compute_dpi
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create(entity_id: fund.entity_id, fund:, valuation:, name: "Dpi", value:, display_value:)

    value = calc.compute_tvpi
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create(entity_id: fund.entity_id, fund:, valuation:, name: "Tvpi", value:, display_value:)

    value = calc.fund_utilization
    display_value = value ? "#{value.round(2) * 100}%" : nil
    FundRatio.create(entity_id: fund.entity_id, fund:, valuation:, name: "Fund Utilization", value:, display_value:)

    value = calc.portfolio_value_to_cost
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create(entity_id: fund.entity_id, fund:, valuation:, name: "Portfolio Value to Cost", value:, display_value:)

    value = calc.paid_in_to_committed_capital
    display_value = value ? "#{value.round(2)}x" : nil
    FundRatio.create(entity_id: fund.entity_id, fund:, valuation:, name: "Paid In to Committed Capital", value:, display_value:)

    value = calc.quarterly_irr
    display_value = value ? "#{value.round(4) * 100}%" : nil
    FundRatio.create(entity_id: fund.entity_id, fund:, valuation:, name: "Quarterly IRR", value:, display_value:)
  end

  def notify(fund, user_id)
    UserAlert.new(user_id:, message: "#{fund.name} fund ratio calculations are now complete. Please refresh the page.", level: "success").broadcast
  end
end
