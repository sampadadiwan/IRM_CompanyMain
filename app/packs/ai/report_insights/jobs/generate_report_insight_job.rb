class GenerateReportInsightJob < ApplicationJob
  include Rails.application.routes.url_helpers

  queue_as :default

  # Generates an AI-driven insight for a specific report.
  # This job can be triggered manually by a user or automatically via a schedule.
  #
  # @param report_id [Integer] The ID of the Report to generate insights for.
  # @param user_id [Integer, nil] The ID of the user triggering the job (nil for system tasks).
  # @param triggered_by_id [Integer, nil] The ID of the entity/user triggering the job.
  def perform(report_id, user_id: nil, triggered_by_id: nil)
    # Use find_by to avoid raising an exception if the report is deleted
    report = Report.find_by(id: report_id)

    if report.blank?
      broadcast_alert(user_id, "Report not found", :danger)
      return
    end

    # Create the insight record to track progress
    report_insight = create_initial_report_insight(report, triggered_by_id)

    # Execute the insight generation logic (Trailblazer operation)
    result = ReportInsightRunner.call(report_insight: report_insight)

    # Update scheduling information for the report
    update_notification_timestamps(report)
    report.save!

    handle_result(result, report, report_insight, user_id)
  rescue StandardError => e
    handle_failure(report_insight, user_id, e.message)
  end

  private

  # Creates the initial ReportInsight record with 'running' status
  def create_initial_report_insight(report, triggered_by_id)
    trigger_type = triggered_by_id.present? ? "manual" : "system"

    ReportInsight.create!(
      report_id: report.id,
      entity_id: report.entity_id,
      status: "running",
      status_message: "In Progress",
      trigger_type: trigger_type,
      triggered_by_id: triggered_by_id
    )
  end

  # Handles the success or failure result from the runner
  def handle_result(result, report, report_insight, user_id)
    if result.success?

      report_link = ActionController::Base.helpers.link_to(
        "View Report Analysis",
        report_insight_path(report_insight),
        class: 'mb-1 badge bg-primary-subtle text-primary',
        target: '_blank',
        rel: 'noopener'
      )
      message = "Report Analysis Generated Successfully.<br> #{report_link}"
      broadcast_alert(user_id, message, :success)
      send_notification(report, report_insight)
    else
      error_msg = "Report Analysis Generation Failed: #{result[:errors].join(', ')}"
      broadcast_alert(user_id, error_msg, :danger)
    end
  end

  # Handles unexpected exceptions during execution
  def handle_failure(report_insight, user_id, error_message)
    msg = "Report Analysis Generation Failed: #{error_message}"
    Rails.logger.error { msg }

    # Ensure we update the insight record if it exists
    report_insight&.update!(status: "failed", status_message: msg)

    broadcast_alert(user_id, msg, :danger)
  end

  # Sends email notification if configured
  def send_notification(report, report_insight)
    return unless report.send_notification

    ReportInsightMailer.with(
      entity_id: report_insight.entity_id,
      report_insight_id: report_insight.id,
      additional_ccs: report.notification_ccs,
      subject: "Report: #{report_insight.report.name} — Key Insights"
    ).send_report_insight_summary.deliver_now
  end

  # Broadcasts a user alert via ActionCable/Turbo
  def broadcast_alert(user_id, message, level)
    return if user_id.blank?

    UserAlert.new(user_id: user_id, message: message, level: level).broadcast
  end

  # Updates the next run time based on the report's schedule
  def update_notification_timestamps(report)
    ran_at = Time.zone.now
    report.notify_last_run_at = ran_at

    interval = (report.notification_repeat_interval.presence || 1).to_i
    unit     = (report.notification_repeat_unit.presence || "days").to_s.downcase

    report.notify_next_run_at = report.calculate_next_run(from: ran_at, interval: interval, unit: unit)
  end
end
