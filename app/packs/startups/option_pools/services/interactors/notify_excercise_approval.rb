class NotifyExcerciseApproval
  include Interactor

  def call
    Rails.logger.debug "Interactor: NotifyExcerciseApproval called"

    if context.excercise.present?
      context.excercise.notify_approval
    else
      Rails.logger.debug "No Excercise specified"
      context.fail!(message: "No Excercise specified")
    end
  end
end
