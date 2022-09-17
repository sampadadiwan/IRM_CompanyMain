class HoldingApproved
  include Interactor

  def call
    Rails.logger.debug "Interactor: HoldingApproved called"

    if context.holding.present?
      holding = context.holding
      context.fail!(message: holding.errors.full_messages) unless holding.update(approved: true, audit_comment: "#{context.audit_comment} : Holding approved")
    else
      Rails.logger.debug "No Holding specified"
      context.fail!(message: "No Holding specified")
    end
  end

  def create_audit_trail(holding)
    context.holding_audit_trail ||= []
    context.parent_id ||= SecureRandom.uuid
    context.holding_audit_trail << HoldingAuditTrail.new(action: :approve_holding, owner: "Holding", quantity: holding.quantity, operation: :modify, ref: holding, entity_id: holding.entity_id, completed: true, parent_id: context.parent_id)
  end

  after do
    create_audit_trail(context.holding)
  end
end
