class CapitalCallRemittanceDocJob < ApplicationJob
  queue_as :doc_gen

  # This is idempotent, we should be able to call it multiple times for the same CapitalCall
  def perform(capital_call_id, user_id)
    error_msg = []
    @capital_call = CapitalCall.find(capital_call_id)
    @capital_call.capital_remittances.each do |cr|
      errors = CapitalRemittanceDocJob.perform_now(cr.id, user_id)
      error_msg.concat(errors) if errors.present?
    end
    if error_msg.present?
      send_notification("Documentation generation completed with errors. Errors will be sent via email", user_id, :danger)
      .
      CapitalRemittancesMailer.with(user_id:, error_msg:).remittance_doc_errors.deliver_now

    else
      send_notification("Documentation generation completed.", user_id, :info)
    end
  end
end
