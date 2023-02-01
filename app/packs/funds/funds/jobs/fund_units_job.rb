class FundUnitsJob < ApplicationJob
  queue_as :low

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(owner_id, owner_type, reason, user_id)
    owner = owner_type.constantize.find(owner_id)
    Chewy.strategy(:sidekiq) do
      case owner_type
      when "CapitalCall"
        DefaultUnitAllocationEngine.new.allocate_call(owner, reason)
      when "CapitalDistribution"
        DefaultUnitAllocationEngine.new.allocate_distribution(owner, reason)
      else
        raise "Cannot generate fund units for #{owner}"
      end
    end

    UserAlert.new(user_id:, message: "Units calculation is now complete.", level: "success").broadcast
  end
end
