class NotifyHoldingApproval
  include Interactor

  def call
    Rails.logger.debug "Interactor: NotifyHoldingApproval called"

    if context.holding.present?
      HoldingMailer.with(holding_id: context.holding.id).notify_approval.deliver_later
    else
      Rails.logger.debug "No Holding specified"
      context.fail!(message: "No Holding specified")
    end
  end
end
