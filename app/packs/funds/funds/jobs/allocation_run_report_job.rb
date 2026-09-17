# Builds the allocation run checker report for one AllocationRun in the background.
#
# The checks are aggregate queries over account_entries, which is one of the largest tables in
# production — a fund with a long history takes long enough that this must not run inside a
# request. The report row is created up front in "Pending" so the report page has something to
# show while the job is still working.
class AllocationRunReportJob < ApplicationJob
  queue_as :default
  # No retry: a failed check is recorded on the report and re-checking is the reviewer's
  # explicit decision, exactly as it is for an allocation run itself.
  sidekiq_options retry: 0

  def perform(report_id)
    report = AllocationRunReport.find_by(id: report_id)
    return if report.nil?

    AllocationRunReportBuild.call(report: report)
  rescue StandardError => e
    Rails.logger.error("AllocationRunReportJob failed for report #{report_id}: #{e.message}")
    report&.update(status: "Error", checked_at: Time.current, message: e.message.truncate(2000))
    raise
  end
end
