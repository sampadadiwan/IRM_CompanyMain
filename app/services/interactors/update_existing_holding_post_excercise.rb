class UpdateExistingHoldingPostExcercise
  include Interactor

  def call
    Rails.logger.debug "Interactor: UpdateExistingHoldingPostExcercise called"

    if context.excercise.present?
      holding = context.excercise.holding.reload
      context.fail!(message: holding.errors.full_messages) unless holding.save
    else
      Rails.logger.debug "No Excercise specified"
      context.fail!(message: "No Excercise specified")
    end
  end

  def create_audit_trail(excercise)
    context.holding_audit_trail ||= []
    context.parent_id ||= SecureRandom.uuid
    context.holding_audit_trail << HoldingAuditTrail.new(action: :update_post_excercise, owner: "Holding", quantity: excercise.holding.quantity, operation: :modify, ref: excercise.holding, entity_id: excercise.entity_id, completed: true, parent_id: context.parent_id)
  end

  after do
    create_audit_trail(context.excercise)
  end
end
