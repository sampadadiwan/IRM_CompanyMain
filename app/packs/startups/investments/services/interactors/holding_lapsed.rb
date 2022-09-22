class HoldingLapsed
  include Interactor

  def call
    Rails.logger.debug "Interactor: HoldingLapsed called"

    if context.holding.present?
      check_lapsed(context.holding)
    else
      Rails.logger.debug "No Holding specified"
      context.fail!(message: "No Holding specified")
    end
  end

  LAPSE_WARNING_DAYS = [30, 20, 10, 5].freeze
  def check_lapsed(holding)
    # Check if the Options have lapsed
    if holding.lapsed?
      holding.lapse
      holding.reload.notify_lapsed
    elsif LAPSE_WARNING_DAYS.include?(holding.days_to_lapse)
      holding.notify_lapse_upcoming
    end
  end

  def create_audit_trail(holding)
    context.holding_audit_trail ||= []
    context.parent_id ||= SecureRandom.uuid
    context.holding_audit_trail << HoldingAuditTrail.new(action: :holding_lapsed, owner: "Holding", quantity: holding.quantity, operation: :modify, ref: holding, entity_id: holding.entity_id, completed: true, parent_id: context.parent_id)
  end

  after do
    create_audit_trail(context.holding)
  end
end
