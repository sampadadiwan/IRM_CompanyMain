class AmlReportJob < ApplicationJob
  queue_as :serial
  sidekiq_options retry: 0

  DELAY_SECONDS = 30
  after_perform do |job|
    if job.arguments.second.present? && job.arguments.last.blank?
      investor_kyc = InvestorKyc.find(job.arguments.first)
      UserAlert.new(user_id: job.arguments.second, message: "Generating AML Report for #{investor_kyc.full_name}", level: "info").broadcast
    end
  end

  def perform(investor_kyc_id, user_id, investor_kyc_ids = nil)
    Chewy.strategy(:sidekiq) do
      if investor_kyc_ids.present?
        process_multiple_kycs(investor_kyc_ids, user_id)
      else
        process_single_kyc(investor_kyc_id, user_id)
      end
    end
  end

  private

  def process_multiple_kycs(investor_kyc_ids, user_id)
    @error_msg ||= []
    @user_id = user_id
    UserAlert.new(user_id: user_id, message: "Generating #{investor_kyc_ids.count} AML Report(s)", level: :info).broadcast if user_id.present?
    investor_kyc_ids.each do |investor_kyc_id|
      process_kyc(investor_kyc_id, user_id)
    end
    email_errors if @error_msg.present?
  end

  def process_single_kyc(investor_kyc_id, user_id)
    investor_kyc = InvestorKyc.find(investor_kyc_id)
    if investor_kyc.full_name.blank?
      msg = "Investor KYC #{investor_kyc_id} does not have full name"
      Rails.logger.error msg
      UserAlert.new(user_id: user_id, message: msg, level: :danger).broadcast if user_id.present?
      return
    end
    aml_report = AmlReport.find_or_create_by(investor_kyc_id:, entity_id: investor_kyc.entity_id, investor_id: investor_kyc.investor_id)
    aml_report.generate
    if Rails.env.test?
      AmlReportAsyncDownloadJob.perform_now(aml_report.id, user_id)
    else
      AmlReportAsyncDownloadJob.set(wait: rand(DELAY_SECONDS).seconds).perform_later(aml_report.id, user_id)
    end
  end

  def process_kyc(investor_kyc_id, user_id)
    investor_kyc = InvestorKyc.find(investor_kyc_id)
    if investor_kyc.full_name.blank?
      msg = "Investor KYC #{investor_kyc_id} does not have full name"
      @error_msg << { msg: msg }
      Rails.logger.error msg
      return
    end
    aml_report = AmlReport.find_or_create_by(investor_kyc_id:, entity_id: investor_kyc.entity_id, investor_id: investor_kyc.investor_id)
    aml_report.generate
    if Rails.env.test?
      AmlReportAsyncDownloadJob.perform_now(aml_report.id, user_id)
    else
      AmlReportAsyncDownloadJob.set(wait: rand(DELAY_SECONDS).seconds).perform_later(aml_report.id, user_id)
    end
  rescue StandardError => e
    msg = "Error generating AML Report for Investor KYC #{investor_kyc_id}: #{e.message}"
    Rails.logger.error msg
    @error_msg << { msg: }
  end

  # email errors to the user
  def email_errors
    error_msg = @error_msg
    user_id = @user_id

    if error_msg.present? && user_id.present?
      msg = "AML Report generation encountered #{error_msg.length} errors. Errors will be sent via email"
      logger.info msg
      UserAlert.new(user_id: user_id, message: msg, level: :danger).broadcast if user_id.present?
      EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg:).doc_gen_errors.deliver_now
    end
  end
end
