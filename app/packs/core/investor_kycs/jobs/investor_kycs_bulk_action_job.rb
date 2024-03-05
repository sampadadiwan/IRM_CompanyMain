class InvestorKycsBulkActionJob < BulkActionJob
  DELAY_SECONDS = 180
  def perform_action(investor_kyc, user_id, bulk_action)
    msg = "#{bulk_action}: #{investor_kyc}"
    send_notification(msg, user_id, :success)
    case bulk_action.downcase

    when "verify"
      investor_kyc.verified = true
      InvestorKycUpdate.call(investor_kyc:, investor_user: false)
    when "bank_verification"
      VerifyKycBankJob.set(wait: rand(DELAY_SECONDS).seconds).perform_later(id)
    when "unverify"
      investor_kyc.verified = false
      InvestorKycUpdate.call(investor_kyc:, investor_user: false)
    when "sendreminder"
      send_reminder(investor_kyc, user_id)
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

  def send_reminder(investor_kyc, user_id)
    if investor_kyc.investor.approved_users.blank?
      msg = "KYC Reminder could not be sent, no users for investor."
      send_notification(msg, user_id, "danger")
      @error_msg << { msg:, id: investor_kyc.id, Kyc: investor_kyc }
    elsif investor_kyc.verified
      msg = "KYC Reminder could not be sent, KYC is verified and uneditable by user"
      send_notification(msg, user_id, "danger")
      @error_msg << { msg:, id: investor_kyc.id, Kyc: investor_kyc }
    else
      # Randomize the time to send the reminder, so we dont flood aws SES
      SendKycFormJob.set(wait: rand(DELAY_SECONDS).seconds).perform_later(investor_kyc.id, reminder: true)
    end
  end
end
