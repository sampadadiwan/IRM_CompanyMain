class AmlReportJob < ApplicationJob
  queue_as :serial
  sidekiq_options retry: 0

  DELAY_SECONDS = 30
  after_perform do |job|
    if job.arguments.second.present?
      investor_kyc = InvestorKyc.find(job.arguments.first)
      UserAlert.new(user_id: job.arguments.second, message: "Generating AML Report for #{investor_kyc.full_name}", level: "info").broadcast
    end
  end

  def perform(investor_kyc_id, user_id)
    Chewy.strategy(:sidekiq) do
      process_single_kyc(investor_kyc_id, user_id)
    end
  end

  private

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
end
