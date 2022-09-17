class NotifyExcerciseApproval
  include Interactor

  def call
    Rails.logger.debug "Interactor: NotifyExcerciseApproval called"

    if context.excercise.present?
      ExcerciseMailer.with(excercise_id: context.excercise.id).notify_approval.deliver_later
    else
      Rails.logger.debug "No Excercise specified"
      context.fail!(message: "No Excercise specified")
    end
  end
end
