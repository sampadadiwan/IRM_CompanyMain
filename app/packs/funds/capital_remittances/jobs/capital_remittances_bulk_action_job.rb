class CapitalRemittancesBulkActionJob < BulkActionJob
  def get_class
    CapitalRemittance
  end

  def record_includes
    [:capital_call, { capital_commitment: :investor_kyc }, :entity, :fund, :investor, :form_type, :documents, :capital_remittance_payments]
  end

  def perform_action(capital_remittance, user_id, bulk_action, params: {})
    msg = "Performing #{bulk_action} on remittance #{capital_remittance}"
    Rails.logger.info(msg + " params: #{params}")
    send_notification(msg, user_id, :success)
    case bulk_action.downcase

    when "verify"
      result = CapitalRemittanceVerify.call(capital_remittance:)
      if result.failure?
        # Surface per-record failures (e.g. duplicate folio_id or zero committed amount
        # validations rolling back the save) so BulkActionJob includes them in the
        # completion notification and error email instead of silently reporting success
        @error_msg << { msg: result[:errors].presence || capital_remittance.errors.full_messages.join(", "),
                        folio_id: capital_remittance.folio_id,
                        capital_remittance_id: capital_remittance.id }
      end
    else
      msg = "Invalid bulk action"
      send_notification(msg, user_id, :error)
    end
  end
end
