module InvestorEntityMerge
  extend ActiveSupport::Concern

  included do
    # This will only merge investor entities - not other types of entities !!!!
    def self.merge(old_entity, new_entity)
      # Many models have a dependency on the investor_entity_id, search schema.rb for t.integer ".*_entity_id" or t.bigint ".*_entity_id"
      # These models will need to be updated to use the new entity_id

      ApprovalResponse.where(response_entity_id: old_entity.id).update_all(response_entity_id: new_entity.id)
      ExpressionOfInterest.where(eoi_entity_id: old_entity.id).update_all(eoi_entity_id: new_entity.id)
      InvestorAccess.where(investor_entity_id: old_entity.id).update_all(investor_entity_id: new_entity.id)

      InvestorNoticeEntry.where(entity_id: old_entity.id, investor_entity_id: old_entity.id).update_all(investor_entity_id: new_entity.id)

      Task.where(for_entity_id: old_entity.id).update_all(for_entity_id: new_entity.id)

      DealInvestor.where(investor_entity_id: old_entity.id).update_all(investor_entity_id: new_entity.id)
      Interest.where(interest_entity_id: old_entity.id).update_all(interest_entity_id: new_entity.id)
      Investor.where(investor_entity_id: old_entity.id).update_all(investor_entity_id: new_entity.id)

      User.where(entity_id: old_entity.id).update_all(entity_id: new_entity.id)
    end
  end
end
