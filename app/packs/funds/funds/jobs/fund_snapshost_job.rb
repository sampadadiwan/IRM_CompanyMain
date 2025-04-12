class FundSnapshotJob < ApplicationJob
  queue_as :low

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(fund_id: nil)
    funds = fund_id ? Fund.where(id: fund_id) : Fund.all

    Chewy.strategy(:sidekiq) do
      funds.each do |fund|
        FundSnapshot.create(fund.attributes)
      end
    end
  end
end
