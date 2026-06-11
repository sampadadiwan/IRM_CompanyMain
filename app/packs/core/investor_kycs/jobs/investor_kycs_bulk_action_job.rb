class InvestorKycsBulkActionJob < BulkActionJob
  DELAY_SECONDS = 180
  def perform_action(investor_kyc, user_id, bulk_action, params: {})
    msg = "#{bulk_action}: #{investor_kyc}"
    Rails.logger.info "Performing #{msg} with #{params}"
    send_notification(msg, user_id, :success)
    case bulk_action.downcase

    when "verify"
      investor_kyc.verified = true
      investor_kyc.submission_status = "verified"
      InvestorKycUpdate.call(investor_kyc:, investor_user: false)
    when "bankverification"
      VerifyBankJob.set(wait: rand(DELAY_SECONDS).seconds).perform_later(obj_class: investor_kyc.class.to_s, obj_id: investor_kyc.id)
    when "unverify"
      investor_kyc.verified = false
      investor_kyc.submission_status = "link_sent"
      InvestorKycUpdate.call(investor_kyc:, investor_user: false)
    when "sendkyclink"
      send_kyc_link(investor_kyc, user_id, custom_notification_id: params[:custom_notification_id])
    when "sendreminder"
      send_reminder(investor_kyc, user_id, custom_notification_id: params[:custom_notification_id])
    when "generateamlreports"
      generate_aml_report(investor_kyc, user_id)
    when "validatedocswithai"
      validate_docs_with_ai(investor_kyc, user_id)
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

  def record_includes
    [:document_folder, :form_type, { investor: [:approved_users, { investor_entity: :entity_setting }] }]
  end

  def validate_docs_with_ai(investor_kyc, user_id)
    if InvestorKycPolicy.new(User.find(user_id), investor_kyc).validate_docs_with_ai? && !investor_kyc.verified
      error_msgs = DocLlmValidationJob.perform_now("InvestorKyc", investor_kyc.id, user_id)
      @error_msg += error_msgs if error_msgs.present?
    else
      msg = investor_kyc.verified ? "Cannot modify verified KYC" : "User not authorized to validate docs with AI for #{investor_kyc}"
      send_notification(msg, user_id, "danger")
      @error_msg << { msg:, id: investor_kyc.id, Kyc: investor_kyc }
    end
    # Sleep to avoid overwhelming the LLM and rate limiting issues
    sleep(2)
  end

  def generate_aml_report(investor_kyc, user_id)
    raise "Investing Entity is blank for Investor Kyc ID #{investor_kyc.id}" if investor_kyc.full_name.blank?

    GenerateAmlReportJob.perform_later(investor_kyc.id, user_id)
  end

  # Initial send — marks KYC as link_sent on first delivery.
  def send_kyc_link(investor_kyc, user_id, custom_notification_id: nil)
    if investor_kyc.investor.approved_users.blank?
      msg = "KYC link could not be sent, no users for investor."
      send_notification(msg, user_id, "danger")
      @error_msg << { msg:, id: investor_kyc.id, Kyc: investor_kyc }
    elsif investor_kyc.submission_completed? || investor_kyc.submission_verified?
      msg = "KYC link not sent, KYC already submitted by investor."
      send_notification(msg, user_id, "danger")
      @error_msg << { msg:, id: investor_kyc.id, Kyc: investor_kyc }
    else
      SendKycFormJob.set(wait: rand(DELAY_SECONDS).seconds).perform_later(investor_kyc.id, reminder: false, custom_notification_id: custom_notification_id)
    end
  end

  def send_reminder(investor_kyc, user_id, custom_notification_id: nil)
    if investor_kyc.investor.approved_users.blank?
      msg = "KYC Reminder could not be sent, no users for investor."
      send_notification(msg, user_id, "danger")
      @error_msg << { msg:, id: investor_kyc.id, Kyc: investor_kyc }
    elsif investor_kyc.verified || investor_kyc.submission_completed? || investor_kyc.submission_verified?
      msg = "KYC Reminder could not be sent, KYC is already submitted or verified."
      send_notification(msg, user_id, "danger")
      @error_msg << { msg:, id: investor_kyc.id, Kyc: investor_kyc }
    else
      SendKycFormJob.set(wait: rand(DELAY_SECONDS).seconds).perform_later(investor_kyc.id, reminder: true, custom_notification_id: custom_notification_id)
    end
  end
end
