class FundReportJob < ApplicationJob
  queue_as :low
  ALL_REPORTS = ["CumulativeFundsRaised"].freeze
  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(entity_id, fund_id, report_name, start_date, end_date, user_id)
    Chewy.strategy(:sidekiq) do
      fund_ids = fund_id.present? ? [fund_id] : Entity.find(entity_id).fund_ids
      fund_ids.each do |fid|
        generate(fid, report_name, start_date, end_date, user_id)
      end
    end

    notify(user_id)
  end

  def generate(fund_id, report_name, start_date, end_date, _user_id)
    if report_name.blank?
      ALL_REPORTS.each do |report_name|
        reporter = report_name.constantize.new
        reporter.generate_report(fund_id, start_date, end_date)
      end
    else
      reporter = report_name.constantize.new
      reporter.generate_report(fund_id, start_date, end_date)
    end
  end

  def notify(user_id)
    UserAlert.new(user_id:, message: "Fund report generation completed. Please refresh the page.", level: "success").broadcast
  end
end
