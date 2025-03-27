class GenerateAmlReportJob < ApplicationJob
  queue_as :serial
  sidekiq_options retry: 0

  DELAY_SECONDS = 30

  def perform(investor_kyc_id, user_id, aml_report_id: nil)
    Chewy.strategy(:sidekiq) do
      if aml_report_id.nil?
        process_single_kyc(investor_kyc_id, user_id)
      else
        fetch_aml_report(aml_report_id, user_id)
      end
    end
  end

  private

  def process_single_kyc(investor_kyc_id, user_id) # rubocop:disable Metrics/MethodLength
    investor_kyc = InvestorKyc.find(investor_kyc_id)
    if investor_kyc.full_name.blank?
      msg = "Investor KYC #{investor_kyc_id} does not have full name"
      Rails.logger.error msg
      UserAlert.new(user_id: user_id, message: msg, level: :danger).broadcast if user_id.present?
      return
    end

    UserAlert.new(user_id: user_id, message: "Generating AML Report(s) for #{investor_kyc.full_name}", level: "info").broadcast
    aml_report = AmlReport.find_or_create_by(investor_kyc_id:, entity_id: investor_kyc.entity_id, investor_id: investor_kyc.investor_id)
    all_aml_reports = [aml_report]
    if investor_kyc.custom_fields["additional_aml_report_attributes"].present?
      investor_kyc.custom_fields["additional_aml_report_attributes"].split(",").each do |name_pan_dob|
        name, pan, dob = name_pan_dob.split(":").map(&:strip)
        if pan == "0"
          pan = nil
        elsif /\A[A-Z]{5}\d{4}[A-Z]\z/.match?(pan.upcase)
          pan = pan.upcase
        elsif user_id.present?
          msg = "Invalid PAN #{pan} for #{name}, please follow format ABCDE1234F"
          Rails.logger.error msg
          UserAlert.new(user_id: user_id, message: msg, level: :danger).broadcast
          errs = [investing_entity: investor_kyc.full_name, aml_report_name: name, error: msg]
          EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg: errs).doc_gen_errors.deliver_now
          next
        end
        dob = Time.zone.parse(dob)
        all_aml_reports << AmlReport.find_or_create_by(investor_kyc_id: investor_kyc_id, entity_id: investor_kyc.entity_id, investor_id: investor_kyc.investor_id, custom_name: name.strip.squeeze(" "), birth_date: dob, PAN: pan)
      end
    end

    if all_aml_reports.count > 1
      all_aml_reports.each do |aml_report_obj|
        if Rails.env.test?
          GenerateAmlReportJob.perform_now(investor_kyc_id, user_id, aml_report_id: aml_report_obj.id)
        else
          GenerateAmlReportJob.set(wait: rand(DELAY_SECONDS).seconds).perform_later(investor_kyc_id, user_id, aml_report_id: aml_report_obj.id)
        end
      end
    else
      fetch_aml_report(aml_report.id, user_id)
    end
  end

  def fetch_aml_report(aml_report_id, user_id)
    aml_report_obj = AmlReport.find(aml_report_id)
    aml_report_obj.generate
    name = aml_report_obj.custom_name.presence || aml_report_obj.investor_kyc.full_name
    if aml_report_obj.request_id.blank? && aml_report_obj.response_data.present?
      # reschedule job if rate limit reached
      if aml_report_obj.response_data.values&.last&.[]('message').present? && aml_report_obj.response_data.values&.last&.[]('message').include?("Rate limit reached")
        Rails.logger.debug { "Rate limit reached for AML API for #{name} for kyc #{aml_report_obj.investor_kyc_id} - Scheduling Fetch Aml Report again" }
        GenerateAmlReportJob.set(wait: rand(DELAY_SECONDS).seconds).perform_later(aml_report_obj.investor_kyc_id, user_id, aml_report_id: aml_report_obj.id)
        return
      end
      msg = "Error Generating AML Report for #{name}"
      msg += " - #{aml_report_obj.response_data.values.last['message']}" if aml_report_obj.response_data.values&.last&.[]('message').present?
      UserAlert.new(user_id: user_id, message: msg, level: :danger).broadcast if user_id.present?
      Rails.logger.error msg
      errs = [investing_entity: aml_report_obj.investor_kyc.full_name, aml_report_name: name, error: msg]
      EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg: errs).doc_gen_errors.deliver_now
    end
    if Rails.env.test?
      AmlReportAsyncDownloadJob.perform_now(aml_report_obj.id, user_id)
    else
      AmlReportAsyncDownloadJob.set(wait: rand(DELAY_SECONDS).seconds).perform_later(aml_report_obj.id, user_id)
    end
  end
end
