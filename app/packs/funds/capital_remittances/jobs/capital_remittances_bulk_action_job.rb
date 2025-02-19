class CapitalRemittancesBulkActionJob < BulkActionJob
  def get_class
    CapitalRemittance
  end

  def perform_action(capital_remittance, user_id, bulk_action, params: {})
    msg = "Performing #{bulk_action} on remittance #{capital_remittance}"
    Rails.logger.info(msg + " params: #{params}")
    send_notification(msg, user_id, :success)
    case bulk_action.downcase

    when "verify"
      CapitalRemittanceVerify.call(capital_remittance:)
    else
      msg = "Invalid bulk action"
      send_notification(msg, user_id, :error)
    end
  end
end
