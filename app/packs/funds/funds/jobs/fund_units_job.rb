class FundUnitsJob < ApplicationJob
  queue_as :low

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(owner_id, owner_type, reason, user_id)
    owner = owner_type.constantize.find(owner_id)

    Chewy.strategy(:sidekiq) do
      case owner_type
      when "CapitalCall"
        reason ||= owner.name
        DefaultUnitAllocationEngine.new.allocate_call(owner, reason, user_id)
      when "CapitalDistribution"
        reason ||= owner.title
        DefaultUnitAllocationEngine.new.allocate_distribution(owner, reason, user_id)
      else
        raise "Cannot generate fund units for #{owner}"
      end
    end

    # Real-time journey progress for the call or distribution (no-op without a journey).
    # Worked examples J2.2 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
    # Worked examples H8 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
    owner.journey_progress!(actor: User.find_by(id: user_id))

    UserAlert.new(user_id:, message: "Units calculation is now complete.", level: "success").broadcast
  end
end
