class ApproveExcercise
  include Interactor::Organizer

  organize  ExcerciseApproved, NewHoldingFromExcercise,
            UpdateExistingHoldingPostExcercise, NotifyExcerciseApproval, CreateAuditTrail

  before do |_organizer|
    context.audit_comment = "Approve Excercise"
  end

  around do |organizer|
    ActiveRecord::Base.transaction do
      organizer.call
    end
  rescue StandardError => e
    Rails.logger.error e.message
    Rails.logger.error context.excercise.to_json
    raise e
  end
end
