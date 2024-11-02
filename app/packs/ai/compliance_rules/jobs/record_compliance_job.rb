class RecordComplianceJob < ApplicationJob
  queue_as :default

  def perform(owner_type, owner_id, user_id)
    model = owner_type.constantize.find(owner_id)
    send_notification("Starting compliance checks..", user_id, :info)
    ComplianceAssistant.run_compliance_checks(model, user_id)
    send_notification("Compliance checks completed for #{model}.", user_id)
  end
end
