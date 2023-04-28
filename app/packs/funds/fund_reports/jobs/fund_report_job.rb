class FundReportJob < ApplicationJob
  queue_as :low
  ALL_REPORTS = ["CumulativeFundsRaised"].freeze
  # This is idempotent, we should be able to call it multiple times for the same CapitalCommitment
  def perform(fund_id, report_name, start_date, end_date)
    Chewy.strategy(:sidekiq) do
      if report_name == "All"
        ALL_REPORTS.each do |report_name|
          reporter = report_name.constantize.new
          reporter.generate_report(fund_id, start_date, end_date)
        end
      else
        reporter = report_name.constantize.new
        reporter.generate_report(fund_id, start_date, end_date)
      end
    end
  end
end
