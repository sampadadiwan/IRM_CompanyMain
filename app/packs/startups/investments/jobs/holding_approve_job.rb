class HoldingApproveJob < ApplicationJob
  queue_as :default

  def perform(type, id)
    Chewy.strategy(:sidekiq) do
      Rails.logger.debug { "HoldingApproveJob: #{type} #{id}" }

      case type
      when "OptionPool"
        holdings = Holding.not_approved.where(option_pool_id: id)
      when "FundingRound"
        holdings = Holding.not_approved.where(funding_round_id: id)
      when "Entity"
        holdings = Holding.not_approved.where(entity: id)
      end

      holdings.find_each(batch_size: 1000) do |holding|
        ApproveHolding.call(holding:)
      end

      # Ensure the approved holdings go thru the vesting algo
      VestedJob.new.perform

      Rails.logger.debug { "HoldingApproveJob: #{type} #{id}. Update #{holdings.count} records." }
    end
  end
end
