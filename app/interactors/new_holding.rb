class NewHolding
  include Interactor

  def call
    Rails.logger.debug "Interactor: NewHolding called"
    if context.holding.present?
      context.holding.audit_comment = "#{context.audit_comment} : New Holding"
      context.holding.save # = Holding.create(context.holding.attributes)
      context.fail!(message: context.holding.errors.full_messages) if context.holding.id.blank?
    else
      Rails.logger.debug "No Holding specified"
      context.fail!(message: "No Holding specified")
    end
  end

  def create_audit_trail(holding)
    context.holding_audit_trail ||= []
    context.parent_id ||= SecureRandom.uuid
    context.holding_audit_trail << HoldingAuditTrail.new(action: :create_holding, owner: "Holding", quantity: holding.quantity, operation: :create_record, ref: holding, entity_id: holding.entity_id, completed: true, parent_id: context.parent_id)
  end

  after do
    create_audit_trail(context.holding)
  end
end
