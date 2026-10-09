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
      # Back to "completed", exactly like the KYC page's UnVerify; Request Updates is what reopens a KYC
      # for the investor. InvestorKycUpdate's journey hook moves the journey back ("Unverified").
      # Only verified KYCs: an unsubmitted one must not be marked submitted by unverifying it.
      # Worked examples E17 — openspec/changes/investor-kyc-journey/design.md#worked-examples
      return unless investor_kyc.submission_verified?

      investor_kyc.verified = false
      investor_kyc.verified_by_id = nil
      investor_kyc.submission_status = "completed"
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

  # Bulk "Check documents": a Document Checks run per KYC, performed here (not queued) so the 2s pacing
  # below still protects the AI provider. Worked example H8 —
  # openspec/changes/document-checks/design.md#worked-examples
  def validate_docs_with_ai(investor_kyc, user_id)
    user = User.find(user_id)
    if InvestorKycPolicy.new(user, investor_kyc).validate_docs_with_ai? && !investor_kyc.verified
      begin
        run = DocChecks::StartRun.call(record: investor_kyc, user:, trigger: "bulk", enqueue: false)
        error_msgs = DocChecks::RunJob.perform_now(run.id)
        @error_msg += error_msgs if error_msgs.present?
      rescue DocChecks::Error::AlreadyRunning => e
        send_notification(e.message, user_id, "warning")
      end
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
