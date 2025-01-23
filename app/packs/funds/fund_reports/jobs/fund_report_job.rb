class FundReportJob < ApplicationJob
  queue_as :low

  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  # rubocop:disable Metrics/ParameterLists
  def perform(entity_id, fund_id, report_name, start_date, end_date, user_id, excel: false, single: false)
    Chewy.strategy(:sidekiq) do
      if SebiReportJob::ALL_REPORTS.include?(report_name)
        SebiReportJob.perform_now(entity_id, fund_id, report_name, start_date, end_date, user_id, excel: excel, single: single)
      elsif CrisilReportJob::ALL_REPORTS.include?(report_name)
        CrisilReportJob.perform_now(entity_id, fund_id, report_name, start_date, end_date, user_id, excel: excel, single: single)
      elsif user_id.present?
        UserAlert.new(message: "Invalid report name: #{report_name}", user_id:, level: "danger").broadcast
      end
    end
  end
end
