class InvestorKycsBulkActionJob < BulkActionJob
  def perform_action(investor_kyc, user_id, bulk_action)
    msg = "#{bulk_action}: #{investor_kyc}"
    send_notification(msg, user_id, :success)
    case bulk_action.downcase

    when "verify"
      investor_kyc.verified = true
      InvestorKycUpdate.call(investor_kyc:, investor_user: false)
    when "unverify"
      investor_kyc.verified = false
      InvestorKycUpdate.call(investor_kyc:, investor_user: false)
    when "sendreminder"
      if investor_kyc.investor.approved_users.blank?
        msg = "KYC Reminder could not be sent, no users for investor."
        send_notification(msg, user_id, "danger")
        @error_msg << { msg:, id: investor_kyc.id, Kyc: investor_kyc }
      elsif investor_kyc.verified
        msg = "KYC Reminder could not be sent, KYC is verified and uneditable by user"
        send_notification(msg, user_id, "danger")
        @error_msg << { msg:, id: investor_kyc.id, Kyc: investor_kyc }
      else
        investor_kyc.send_kyc_form(reminder: true)
      end
    else
      msg = "Invalid bulk action"
      send_notification(msg, user_id, :error)
    end
  rescue Exception => e
    msg = "Error in #{bulk_action} for #{investor_kyc} #{e.message}"
    send_notification(msg, user_id, "danger")
    @error_msg << { msg:, id: investor_kyc.id, Kyc: investor_kyc }
  end

  def get_class
    InvestorKyc
  end
end
