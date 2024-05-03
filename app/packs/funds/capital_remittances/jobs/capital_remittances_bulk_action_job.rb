class CapitalRemittancesBulkActionJob < BulkActionJob
  def get_class
    CapitalRemittance
  end

  def perform_action(capital_remittance, user_id, bulk_action, _params: {})
    msg = "#{bulk_action}: #{capital_remittance}"
    send_notification(msg, user_id, :success)
    case bulk_action.downcase

    when "verify"
      capital_remittance.verify_remittance
    else
      msg = "Invalid bulk action"
      send_notification(msg, user_id, :error)
    end
  end
end
