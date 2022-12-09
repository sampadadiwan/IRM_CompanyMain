class FundCalcJob < ApplicationJob
  queue_as :low

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(fund_id)
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
    end
  end
end
