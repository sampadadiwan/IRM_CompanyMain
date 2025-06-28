class GenerateAmlReportJob < ApplicationJob
  queue_as :serial
  sidekiq_options retry: 0

  DELAY_SECONDS = 30

  def perform(investor_kyc_id, user_id, aml_report_id: nil, all_aml_report_ids: nil)
    Chewy.strategy(:sidekiq) do
      if all_aml_report_ids.present?
        process_multiple_reports(all_aml_report_ids, user_id)
      elsif aml_report_id.nil?
        process_single_kyc(investor_kyc_id, user_id)
      else
        fetch_aml_report(aml_report_id, user_id)
      end
    end
  end

  private

  def process_single_kyc(investor_kyc_id, user_id)
    investor_kyc = InvestorKyc.find(investor_kyc_id)
    return unless validate_investor_kyc(investor_kyc, user_id)

    UserAlert.new(user_id: user_id, message: "Generating AML Report(s) for #{investor_kyc.full_name}", level: "info").broadcast
    aml_report = AmlReport.find_or_create_by(investor_kyc_id:, entity_id: investor_kyc.entity_id, investor_id: investor_kyc.investor_id)
    all_aml_reports, errs = handle_additional_attributes(investor_kyc, aml_report, user_id)

    send_error_alerts(errs, user_id) if errs.any?
    schedule_or_fetch_reports(all_aml_reports, investor_kyc_id, user_id)
  end

  def validate_investor_kyc(investor_kyc, user_id)
    if investor_kyc.full_name.blank?
      msg = "Investor KYC #{investor_kyc.id} does not have full name"
      Rails.logger.error msg
      UserAlert.new(user_id: user_id, message: msg, level: :danger).broadcast if user_id.present?
      return false
    end
    true
  end

  def handle_additional_attributes(investor_kyc, aml_report, user_id)
    all_aml_reports = [aml_report]
    errs = []
    if investor_kyc.custom_fields["additional_aml_report_attributes"].present?
      investor_kyc.custom_fields["additional_aml_report_attributes"].split(",").each do |name_pan_dob|
        name, pan, dob = parse_attributes(name_pan_dob)
        pan, dob, error = validate_pan_and_dob(pan, dob, name, investor_kyc.full_name, user_id)
        if error
          errs << error
          next
        end
        all_aml_reports << AmlReport.find_or_create_by(investor_kyc_id: investor_kyc.id, entity_id: investor_kyc.entity_id, investor_id: investor_kyc.investor_id, custom_name: name.strip.squeeze(" "), birth_date: dob, PAN: pan)
      end
    end
    [all_aml_reports, errs]
  end

  def parse_attributes(name_pan_dob)
    name, pan, dob = name_pan_dob.split(":").map(&:strip)
    pan = nil if pan == "0"
    dob = nil if dob == "0" || dob.blank?
    [name, pan, dob]
  end

  def validate_pan_and_dob(pan, dob, name, full_name, user_id)
    errs = nil
    if pan && !/\A[A-Z]{5}\d{4}[A-Z]\z/.match?(pan.upcase)
      msg = "Invalid PAN #{pan} for #{name}, please follow format ABCDE1234F"
      Rails.logger.error msg
      UserAlert.new(user_id: user_id, message: msg, level: :danger).broadcast if user_id.present?
      errs = { investing_entity: full_name, aml_report_name: name, error: msg }
    end
    if dob
      begin
        dob = Time.zone.parse(dob)
      rescue ArgumentError
        msg = "Invalid date of birth #{dob} for #{name}, please follow format DD/MM/YYYY"
        errs = { investing_entity: full_name, aml_report_name: name, error: msg }
      end
    end
    [pan&.upcase, dob, errs]
  end

  def send_error_alerts(errs, user_id)
    EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg: errs).doc_gen_errors.deliver_now
  end

  def schedule_or_fetch_reports(all_aml_reports, investor_kyc_id, user_id)
    if all_aml_reports.count > 1
      job_method = Rails.env.test? ? :perform_now : :perform_later
      GenerateAmlReportJob.send(job_method, investor_kyc_id, user_id, all_aml_report_ids: all_aml_reports.map(&:id))
    else
      fetch_aml_report(all_aml_reports.first.id, user_id)
    end
  end

  def process_multiple_reports(all_aml_report_ids, user_id)
    errs = []
    user = User.find(user_id)
    all_aml_report_ids.each_with_index do |aml_report_id, index|
      # Add a delay between API calls to avoid rate limiting, but not for the first one.
      sleep(rand(DELAY_SECONDS)) if index.positive? && !Rails.env.test?
      errs += fetch_aml_report(aml_report_id, user_id, send_mailer: false)
    end

    EntityMailer.with(entity_id: user.entity_id, user_id:, error_msg: errs).doc_gen_errors.deliver_now if errs.any?
  end

  def fetch_aml_report(aml_report_id, user_id, send_mailer: true)
    aml_report_obj = AmlReport.find(aml_report_id)
    aml_report_obj.generate
    name = aml_report_obj.custom_name.presence || aml_report_obj.investor_kyc.full_name
    errs = []
    if aml_report_obj.request_id.blank? && aml_report_obj.response_data.present?
      # reschedule job if rate limit reached
      if aml_report_obj.response_data.values&.last&.[]('message')&.include?("Rate limit reached")
        Rails.logger.debug { "Rate limit reached for AML API for #{name} for kyc #{aml_report_obj.investor_kyc_id} - Scheduling Fetch Aml Report again" }
        GenerateAmlReportJob.set(wait: rand(DELAY_SECONDS).seconds).perform_later(aml_report_obj.investor_kyc_id, user_id, aml_report_id: aml_report_obj.id)
        return errs
      end
      msg = "Error Generating AML Report for #{name}"
      msg += " - #{aml_report_obj.response_data.values.last['message']}" if aml_report_obj.response_data.values&.last&.[]('message').present?
      UserAlert.new(user_id: user_id, message: msg, level: :danger).broadcast if user_id.present?
      Rails.logger.error msg
      errs << { investing_entity: aml_report_obj.investor_kyc.full_name, aml_report_name: name, error: msg }
      EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg: errs).doc_gen_errors.deliver_now if send_mailer
    end
    if Rails.env.test?
      AmlReportAsyncDownloadJob.perform_now(aml_report_obj.id, user_id)
    else
      AmlReportAsyncDownloadJob.set(wait: rand(DELAY_SECONDS).seconds).perform_later(aml_report_obj.id, user_id)
    end
    errs
  end
end
