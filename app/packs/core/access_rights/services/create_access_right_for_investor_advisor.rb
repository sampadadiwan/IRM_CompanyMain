class CreateAccessRightForInvestorAdvisor < Trailblazer::Operation
  step :find_or_create_access_right

  def find_or_create_access_right(ctx, entity_id:, owner:, user_id:, access_type:, metadata:, **) # rubocop:disable Metrics/ParameterLists
    access_right = AccessRight.find_by(entity_id: entity_id, owner: owner, user_id: user_id)
    if access_right.nil?
      access_right = AccessRight.new(entity_id: entity_id, owner: owner, user_id: user_id, access_type: access_type, metadata: metadata)
      unless access_right.save
        ctx[:errors] = access_right.errors.full_messages.join(", ")
        return false
      end
    end
    ctx[:access_right] = access_right
    true
  end
end
