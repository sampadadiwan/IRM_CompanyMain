class CreateInvestorAdvisorEntity < Trailblazer::Operation
  step :find_or_create_entity

  def find_or_create_entity(ctx, name:, primary_email:, **)
    entity = Entity.find_by(name: name)
    if entity.nil?
      entity = Entity.new(name: name, primary_email: primary_email, entity_type: "Investor Advisor")
      unless entity.save
        ctx[:entity] = entity
        ctx[:errors] = entity.errors.full_messages.join(", ")
        return false
      end
    end
    ctx[:entity] = entity
    true
  end
end
