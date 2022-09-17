class ApprovePool
  include Interactor

  def call
    Rails.logger.debug "Interactor: ApprovePool called"

    if context.option_pool.present?
      option_pool = context.option_pool
      context.fail!(message: option_pool.errors.full_messages) unless option_pool.update(approved: true, audit_comment: "#{context.audit_comment} :  Approve Pool")
    else
      Rails.logger.debug "No OptionPool specified"
      context.fail!(message: "No OptionPool specified")
    end
  end

  def create_audit_trail(option_pool)
    context.holding_audit_trail ||= []
    context.parent_id ||= SecureRandom.uuid
    context.holding_audit_trail << HoldingAuditTrail.new(action: :approve_option_pool, owner: "OptionPool", quantity: option_pool.number_of_options, operation: :modify, ref: option_pool, entity_id: option_pool.entity_id, completed: true, parent_id: context.parent_id)
  end

  after do
    create_audit_trail(context.option_pool)
  end
end
