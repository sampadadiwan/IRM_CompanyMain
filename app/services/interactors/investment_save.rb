class InvestmentSave
  include Interactor

  def call
    Rails.logger.debug "Interactor: InvestmentSave called"
    if context.investment
      investment = context.investment
      context.fail!(message: investment.errors.full_messages) unless investment.save
    else
      Rails.logger.debug "No investment specified"
      context.fail!(message: "No investment specified")
    end
  end

  def create_audit_trail(investment)
    context.holding_audit_trail ||= []
    context.parent_id ||= SecureRandom.uuid
    context.holding_audit_trail << HoldingAuditTrail.new(action: :save_investment, owner: "investment", quantity: investment.quantity, operation: context.holding_audit_trail_op, ref: investment, entity_id: investment.entity_id, completed: true, parent_id: context.parent_id)
  end

  after do
    create_audit_trail(context.investment)
  end

  before do
    context.holding_audit_trail_op = context.investment.new_record? ? :create_record : :modify
  end
end
