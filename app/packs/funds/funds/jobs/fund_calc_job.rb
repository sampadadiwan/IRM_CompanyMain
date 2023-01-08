class FundCalcJob < ApplicationJob
  queue_as :low

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(fund_id, user_id)
    Chewy.strategy(:sidekiq) do
      @fund = Fund.find(fund_id)

      # Compute and store all the calcs
      @fund.xirr = @fund.compute_xirr
      @fund.moic = @fund.compute_moic
      @fund.rvpi = @fund.compute_rvpi
      @fund.dpi = @fund.compute_dpi
      @fund.tvpi = @fund.compute_tvpi

      # We need to set this, else this job gets called recursively
      @fund.update_by_fund_calc = true

      @fund.save

      notify(@fund, user_id)
    end
  end

  def notify(_fund, user_id)
    UserAlert.new(user_id:, message: "Fund ratio calculations are now complete. Please refresh the page.", level: "success").broadcast
  end
end
