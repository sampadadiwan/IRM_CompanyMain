class ExcerciseApproved
  include Interactor

  def call
    Rails.logger.debug "Interactor: ExcerciseApproved called"

    if context.excercise.present?
      excercise = context.excercise

      context.fail!(message: excercise.errors.full_messages) unless
              excercise.update(approved: true, approved_on: Time.zone.today, audit_comment: "#{context.audit_comment} : Excercise approved")

      context.holding = excercise.holding
    else
      Rails.logger.debug "No Excercise specified"
      context.fail!(message: "No Excercise specified")
    end
  end

  def create_audit_trail(excercise)
    context.holding_audit_trail ||= []
    context.parent_id ||= SecureRandom.uuid
    context.holding_audit_trail << HoldingAuditTrail.new(action: :approve_excercise, owner: "Excercise", quantity: excercise.quantity, operation: :modify, ref: excercise, entity_id: excercise.entity_id, completed: true, parent_id: context.parent_id)
  end

  after do
    create_audit_trail(context.excercise)
  end
end
