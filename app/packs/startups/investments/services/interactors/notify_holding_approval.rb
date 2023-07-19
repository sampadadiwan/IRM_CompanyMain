class NotifyHoldingApproval
  include Interactor

  def call
    Rails.logger.debug "Interactor: NotifyHoldingApproval called"

    if context.holding.present?
      context.holding.notify_approval
    else
      Rails.logger.debug "No Holding specified"
      context.fail!(message: "No Holding specified")
    end
  end
end
