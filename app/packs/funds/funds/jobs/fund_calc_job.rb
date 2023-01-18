class FundCalcJob < ApplicationJob
  queue_as :low

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(fund_id, user_id)
    Chewy.strategy(:sidekiq) do
      fund = Fund.find(fund_id)

      valuation = fund.valuations.order(valuation_date: :asc).last
      calc = FundCalcs.new(fund, valuation)

      # Blow off prev fund ratio calcs for this valuation
      FundRatio.where(fund:, valuation:).delete_all

      # Create the ratios
      FundRatio.create(entity_id: fund.entity_id, fund:, valuation:, name: "Xirr", value: calc.compute_xirr)
      FundRatio.create(entity_id: fund.entity_id, fund:, valuation:, name: "Moic", value: calc.compute_moic)
      FundRatio.create(entity_id: fund.entity_id, fund:, valuation:, name: "Rvpi", value: calc.compute_rvpi)
      FundRatio.create(entity_id: fund.entity_id, fund:, valuation:, name: "Dpi", value: calc.compute_dpi)
      FundRatio.create(entity_id: fund.entity_id, fund:, valuation:, name: "Tvpi", value: calc.compute_tvpi)

      # Notify the user
      notify(fund, user_id)
    end
  end

  def notify(fund, user_id)
    UserAlert.new(user_id:, message: "#{fund.name} fund ratio calculations are now complete. Please refresh the page.", level: "success").broadcast
  end
end
