# Background job to send notification reminders to Portfolio Companies (PortCos) for KPI reporting.
# This job handles asynchronous processing of multiple PortCos and reports errors via email.
class SendPortcoNotificationJob < ApplicationJob
  queue_as :default

  # @param portfolio_company_ids [Array<Integer>, Integer] One or more Portfolio Company (Investor) IDs.
  # @param user_id [Integer] The ID of the user triggering the notification.
  # @param as_of [String, NilClass] Optional ISO date string. If provided, targets a specific report date.
  def perform(portfolio_company_ids, user_id:, as_of: nil)
    portfolio_company_ids = Array(portfolio_company_ids)
    user = User.find(user_id)
    @error_msgs = []

    # Process each PortCo individually. Rescuing at this level ensures one failure
    # doesn't prevent other PortCos from receiving notifications.
    portfolio_company_ids.each do |pc_id|
      process_portfolio_company(pc_id, user, as_of)
    rescue StandardError => e
      error_info = "Critical error processing PortfolioCompany ID #{pc_id}: #{e.message}"
      Rails.logger.error error_info
      @error_msgs << { pc_id: pc_id, message: error_info }
    end

    # If any errors occurred during the bulk process, notify the user.
    send_error_email(user) if @error_msgs.present?
  end

  private

  # Finds or creates a KPI report for the PortCo and triggers the notification service.
  def process_portfolio_company(pc_id, user, as_of_param)
    portfolio_company = Investor.find(pc_id)
    Rails.logger.debug { "--- SendPortcoNotificationJob DEBUG [PC: #{pc_id}] ---" }

    # 1. Determine which KPI report to target
    kpi_report = if as_of_param.present?
                   # Use the explicitly provided date
                   as_of = Date.local_parse(as_of_param)
                   KpiReport.find_or_create_by!(
                     entity_id: user.entity_id,
                     portfolio_company_id: portfolio_company.id,
                     as_of: as_of,
                     tag_list: "Actual"
                   ) do |report|
                     report.user_id = user.id
                     report.period = "Quarter"
                     report.enable_portco_upload = true
                   end
                 else
                   # Fallback to the intelligent quarter-end shell logic
                   find_or_create_kpi_report_shell(portfolio_company, user)
                 end

    # 2. Authorization check: Ensure the user still has permission for this PortCo/Report
    policy = KpiReportPolicy.new(user, kpi_report)
    unless policy.send_portco_notification?
      error_msg = "User does not have permission to send notification for this portfolio company."
      Rails.logger.debug { "Permission Denied: #{error_msg}" }
      @error_msgs << {
        pc_id: pc_id,
        pc_name: portfolio_company.name,
        message: error_msg
      }
      return
    end

    # 3. Trigger the notification operation
    result = SendPortcoNotification.call(model: kpi_report, entity_id: user.entity_id)

    # 4. Handle service-level failures
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

  # Sends a summary of processing errors to the triggering user.
  # Matches the implementation in KpiCumulateJob.
  def send_error_email(user)
    msg = "Errors in sending PortCo KPI notifications."

    # Convert error messages to a format compatible with the EntityMailer's notify_errors view.
    # The view expects an Enumerable of key-value pairs where values are strings.
    formatted_errors = @error_msgs.map.with_index do |err, _idx|
      ["#{err[:pc_name] || 'Unknown PortCo'} (ID: #{err[:pc_id]})", err[:message]]
    end

    EntityMailer.with(
      to: user.email,
      error_msg: formatted_errors,
      subject: msg
    ).notify_errors.deliver_now
  end
end
