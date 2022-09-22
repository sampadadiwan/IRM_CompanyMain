class NotifyHoldingCancelled
  include Interactor

  def call
    Rails.logger.debug "Interactor: NotifyHoldingCancelled called"

    if context.holding.present?
      context.holding.reload.notify_cancellation
    else
      Rails.logger.debug "No Holding specified"
      context.fail!(message: "No Holding specified")
    end
  end
end
