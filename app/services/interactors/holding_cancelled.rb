class HoldingCancelled
  include Interactor

  def call
    Rails.logger.debug "Interactor: HoldingCancelled called"

    if context.holding.present?
      context.fail!(message: holding.errors.full_messages) unless cancel(context.holding, context.all_or_unvested)
    else
      Rails.logger.debug "No Holding specified"
      context.fail!(message: "No Holding specified")
    end
  end

  def cancel(holding, all_or_unvested)
    case all_or_unvested
    when "all"
      holding.update(cancelled: true, unvested_cancelled_quantity: holding.net_unvested_quantity,
                     unexcercised_cancelled_quantity: holding.net_avail_to_excercise_quantity,
                     audit_comment: "#{context.audit_comment} : Cancelled All")
    # puts "### all Calling compute_vested_quantity #{holding.vested_quantity}"
    when "unvested"
      holding.update(cancelled: true, unvested_cancelled_quantity: holding.net_unvested_quantity,
                     audit_comment: "#{context.audit_comment} : Cancelled Unvested")
    # puts "### unvested Calling compute_vested_quantity #{holding.vested_quantity}"
    else
      holding.errors.add(:cancelled, "Invalid option provided, all or unvested only")
      false
    end
  end

  def create_audit_trail(holding)
    context.holding_audit_trail ||= []
    context.parent_id ||= SecureRandom.uuid
    context.holding_audit_trail << HoldingAuditTrail.new(action: :holding_cancelled, owner: "Holding", quantity: holding.quantity, operation: :modify, ref: holding, entity_id: holding.entity_id, completed: true, parent_id: context.parent_id)
  end

  after do
    create_audit_trail(context.holding)
  end
end
