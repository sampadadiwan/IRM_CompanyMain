# Background job to send notification reminders to Portfolio Companies (PortCos) for KPI reporting.
# This job handles asynchronous processing of multiple PortCos and reports errors via email.
class SendPortcoNotificationJob < ApplicationJob
  queue_as :default

  # @param portfolio_company_ids [Array<Integer>, Integer] One or more Portfolio Company (Investor) IDs.
  # @param user_id [Integer] The ID of the user triggering the notification.
  # @param as_of [String, NilClass] Optional ISO date string. If provided, targets a specific report date.
  # @param period [String, NilClass] Optional period string (e.g., 'Month', 'Quarter', 'Year').
  # @param kpi_report_id [Integer, NilClass] Optional: send for this exact report (the report page's
  #   "Send upload request" button) instead of finding one by date and period.
  def perform(portfolio_company_ids, user_id:, as_of: nil, period: nil, kpi_report_id: nil)
    portfolio_company_ids = Array(portfolio_company_ids)
    user = User.find(user_id)
    @error_msgs = []

    # Process each PortCo individually. Rescuing at this level ensures one failure
    # doesn't prevent other PortCos from receiving notifications.
    portfolio_company_ids.each do |pc_id|
      process_portfolio_company(pc_id, user, as_of, period, kpi_report_id)
    rescue StandardError => e
      error_info = "Critical error processing PortfolioCompany ID #{pc_id}: #{e.message}"
      Rails.logger.error error_info
      @error_msgs << { pc_id: pc_id, message: error_info }
    end

    # If any errors occurred during the bulk process, notify the user.
    send_error_email(user) if @error_msgs.present?
  end

  # The report a reminder for this date and period targets — found, or created as an upload shell.
  # Public so the controller can create the same shell up front for a single company and send the
  # user straight to it; the job then finds that report rather than making a second one.
  def self.find_or_create_dated_report(portfolio_company, user, as_of_param, period_param)
    KpiReport.find_or_create_by!(
      entity_id: user.entity_id,
      portfolio_company_id: portfolio_company.id,
      as_of: Date.local_parse(as_of_param),
      period: period_param.presence || "Quarter",
      tag_list: "Actual"
    ) do |report|
      report.user_id = user.id
      report.enable_portco_upload = true
    end
  end

  private

  # Finds or creates a KPI report for the PortCo and triggers the notification service.
  def process_portfolio_company(pc_id, user, as_of_param, period_param, kpi_report_id = nil)
    portfolio_company = Investor.find(pc_id)
    Rails.logger.debug { "--- SendPortcoNotificationJob DEBUG [PC: #{pc_id}] ---" }

    # 1. Determine which KPI report to target
    kpi_report = if kpi_report_id.present?
                   # The report page asked for this exact report — never find or create another one
                   # (its tag or period may not match what a date lookup would pick).
                   # Worked examples H18 — openspec/changes/kpi-report-journey/design.md#worked-examples
                   KpiReport.find_by!(id: kpi_report_id, entity_id: user.entity_id, portfolio_company_id: portfolio_company.id)
                 elsif as_of_param.present?
                   # Use the explicitly provided date
                   self.class.find_or_create_dated_report(portfolio_company, user, as_of_param, period_param)
                 else
                   # Fallback to the intelligent quarter-end shell logic
                   find_or_create_kpi_report_shell(portfolio_company, user)
                 end

    # 1b. The report page's button sends once: a second click queued before the first job ran finds the
    # link already sent and stops (resending is the grid's Send Reminder). Worked examples H18.
    if kpi_report_id.present? && kpi_report.link_sent_at.present?
      Rails.logger.info "SendPortcoNotificationJob: report #{kpi_report.id} link already sent — skipping duplicate request"
      return
    end

    # 2. Skip portcos that have already submitted — no need to nag them.
    if kpi_report.status_submitted? || kpi_report.status_reviewed?
      Rails.logger.info "SendPortcoNotificationJob: skipping #{portfolio_company.name} — already #{kpi_report.status}"
      return
    end

    # 3. Authorization check
    policy = KpiReportPolicy.new(user, kpi_report)
    unless policy.send_portco_notification?
      @error_msgs << {
        pc_id: pc_id,
        pc_name: portfolio_company.name,
        message: "You do not have permission to send notifications for this portfolio company."
      }
      return
    end

    # The fund asked for this period, so the report is a request and gets the KPI report journey — even
    # when the email below can't go out (no portal users): the step bar then shows what's missing.
    # Worked examples H15 — openspec/changes/kpi-report-journey/design.md#worked-examples
    kpi_report.start_journey!(user)

    # 3b. Business logic check: portco must have at least one approved portal user who gets KPI emails —
    # the same people SendPortcoNotification emails (approved, tagged Kpi or untagged)
    if portfolio_company.notification_users(kpi_report, with_tag: 'Kpi').empty?
      @error_msgs << {
        pc_id: pc_id,
        pc_name: portfolio_company.name,
        message: "No approved portal users found. Add an approved user for this company under Stakeholders before sending a reminder."
      }
      return
    end

    # 4. Trigger the notification operation
    result = SendPortcoNotification.call(model: kpi_report, entity_id: user.entity_id)

    # 5. Handle service-level failures
    if result.success?
      send_notification_msg = "Successfully sent notification for #{portfolio_company.name} targeting report as of #{I18n.l(kpi_report.as_of)}."
      send_notification(send_notification_msg, user.id)
    else
      @error_msgs << {
        pc_id: pc_id,
        pc_name: portfolio_company.name,
        message: "Failed to send notification: #{result[:error] || 'Unknown error'}"
      }
    end
  end

  # Intelligent shell creation logic:
  # - Usually targets the end of the current quarter.
  # - If current date is >15 days past quarter end and previous quarter report is empty, reuses previous quarter.
  def find_or_create_kpi_report_shell(portfolio_company, user)
    current_quarter_end = Time.zone.today.end_of_quarter
    as_of = current_quarter_end
    period = "Quarter"

    # If we are well into a new quarter, check if the previous one was actually reported.
    if Time.zone.today > (current_quarter_end + 15.days)
      previous_quarter_end = (Time.zone.today - 3.months).end_of_quarter
      previous_report = KpiReport.find_or_create_by!(
        entity_id: user.entity_id,
        portfolio_company_id: portfolio_company.id,
        as_of: previous_quarter_end,
        period: period,
        tag_list: "Actual"
      ) do |report|
        report.user_id = user.id
        report.enable_portco_upload = true
      end

      # If the previous report exists but has no data, target it instead of the current quarter.
      as_of = previous_report.kpis.none? ? previous_quarter_end : current_quarter_end
      return previous_report if as_of == previous_quarter_end
    end

    # Standard case: Target the current quarter end shell.
    KpiReport.find_or_create_by!(
      entity_id: user.entity_id,
      portfolio_company_id: portfolio_company.id,
      as_of: as_of,
      period: period,
      tag_list: "Actual"
    ) do |report|
      report.user_id = user.id
      report.enable_portco_upload = true
    end
  end

  # Sends a summary of processing errors to the triggering user — both as a
  # real-time in-app alert and as an email for reference.
  def send_error_email(user)
    lines = @error_msgs.map { |err| "<strong>#{err[:pc_name]}</strong>: #{err[:message]}" }
    html = "<strong>Errors sending KPI notifications:</strong><ul>#{lines.map { |l| "<li>#{l}</li>" }.join}</ul>"

    # Broadcast inline so the user sees it immediately in the browser.
    send_notification(html, user.id, "danger")

    # Also email for a persistent record.
    formatted_errors = @error_msgs.map { |err| ["#{err[:pc_name]} (ID: #{err[:pc_id]})", err[:message]] }
    EntityMailer.with(
      to: user.email,
      error_msg: formatted_errors,
      subject: "Errors sending PortCo KPI notifications",
      entity_id: user.entity_id,
      context: error_context(entity_id: user.entity_id, "Portfolio companies with errors" => @error_msgs.size)
    ).notify_errors.deliver_now
  end
end
