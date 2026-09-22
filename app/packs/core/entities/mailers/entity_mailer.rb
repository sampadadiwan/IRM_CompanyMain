class EntityMailer < ApplicationMailer
  def notify_created
    @entity = Entity.find params[:id]
    mail(to: ENV.fetch('SUPPORT_EMAIL_TO', nil),
         subject: "#{ENV.fetch('BASE_DOMAIN', nil)} New Entity created #{@entity.name}")
  end

  def doc_gen_errors
    setup_defaults
    add_support_to_cc
    @error_msg = params[:error_msg]
    @main_error = params[:main_error]
    @context = error_context
    subject = params[:subject].presence || params[:main_error].presence || "#{ENV.fetch('BASE_DOMAIN', nil)} #{default_error_subject}"
    mail(from: @from, to: @to, cc: @cc, subject:)
  end

  def spa_job_errors
    add_support_to_cc
    @error_msg = params[:error_msg]
    @context = error_context
    subject = params[:subject].presence || "#{ENV.fetch('BASE_DOMAIN', nil)} #{default_error_subject}"
    mail(from: @from, to: @to, cc: @cc, subject:)
  end

  # Sends a consolidated compliance reminder to portfolio company employees
  # listing exactly which items (KPIs, Documents, Valuations) are missing.
  #
  # @param params[:entity_id] [Integer] the portfolio company entity
  # @param params[:requesting_entity_id] [Integer] the fund entity requesting submissions
  # @param params[:missing_items] [Array<String>] list of missing categories, e.g. ["KPIs", "Valuations"]
  # @param params[:period_label] [String, nil] human-readable period, e.g. "Q2 2026"
  def kpi_reminder
    @entity = Entity.find params[:entity_id]
    @requesting_entity = Entity.find params[:requesting_entity_id]
    @missing_items = params[:missing_items] || ["KPIs"]
    @period_label = params[:period_label]
    # Changed: prefer explicit recipient_emails from agent config so reminders
    # reach the FM-configured contacts (e.g. portfolio company CFO) instead of
    # the fund entity's employees. Falls back to entity employees for legacy
    # callers (entities_controller#kpi_reminder) that don't pass recipient_emails.
    @to ||= params[:recipient_emails].presence || @entity.employees.pluck(:email).join(',')
    subject = "Action Required: Missing #{@missing_items.join(', ')} for #{@period_label || 'current period'}"
    send_mail(subject:)
  end

  def add_support_to_cc
    support_email = ENV.fetch('SUPPORT_EMAIL_TO', nil)
    @cc.present? ? @cc += ",#{support_email}" : @cc = support_email
  end

  def notify_errors
    @error_msg = params[:error_msg]
    # Optional — a link back into the app pre-filtered to whatever this error report is about
    # (e.g. SkippedNotificationReportJob links to the skipped notifications it just reported).
    @filter_url = params[:filter_url]
    @filter_label = params[:filter_label]
    # Who/what/where block rendered above the error list — see ErrorReportContext.
    @context = error_context
    subject = "#{ENV.fetch('BASE_DOMAIN', nil)} #{params[:subject].presence || default_error_subject}"
    to = params[:to].presence || support_emails
    mail(to:, subject:)
  end

  def notify_info
    @msg = params[:msg]
    subject = params[:subject].presence || "#{ENV.fetch('BASE_DOMAIN', nil)} INFO"
    mail(to: support_emails, subject:)
  end

  def send_report
    setup_defaults
    add_support_to_cc
    @report_data = begin
      JSON.parse(params[:report_data])
    rescue StandardError
      []
    end
    @title = "#{ENV.fetch('BASE_DOMAIN', nil)} #{params[:subject].presence}"

    Rails.logger.info("[EntityMailer] Sending report email with #{@report_data.size} rows.")
    Rails.logger.debug(@report_data.inspect)

    mail(
      from: @from,
      to: @to,
      cc: @cc,
      subject: @title
    )
  end

  private

  # The caller's own diagnostic block when it supplied one (jobs pass `context: error_context`),
  # otherwise everything still recoverable from the mailer's params — so callers that predate
  # ErrorReportContext at least name the user and entity instead of nothing at all.
  def error_context
    params[:context].presence || ErrorReportContext.for_mailer(user: @user, entity: @entity)
  rescue StandardError => e
    # Belt and braces: ErrorReportContext already rescues internally, but this mailer's whole
    # job is to report a failure. It must never be the thing that fails.
    Rails.logger.error("EntityMailer#error_context failed: #{e.class}: #{e.message}")
    nil
  end

  # "Errors in TrackingCurrencyJob" beats a bare "Errors" in a support inbox that receives
  # these from a dozen different jobs. Falls back to "Errors" when the source is unknown.
  def default_error_subject
    source = @context.is_a?(Hash) ? @context["Source"] : nil
    source.present? ? "Errors in #{source}" : "Errors"
  end

  def support_emails
    # Fetch the default support email from the environment
    default_to = ENV.fetch('SUPPORT_EMAIL_TO', nil)
    # If no entity_id is provided, default to the original support email
    return default_to unless params[:entity_id]

    @entity ||= Entity.find_by(id: params[:entity_id]) # rubocop:disable Rails/FindByOrAssignmentMemoization
    return default_to unless @entity

    # Retrieve all emails of users associated with enabled SupportClientMapping for this entity
    mapping_emails = @entity.support_client_mappings.where(enabled: true).joins(:user).pluck('users.email')
    # If no active support mappings are found, fall back to the default support email
    return default_to if mapping_emails.empty?

    # Return the mapping-specific emails as a comma-separated string
    mapping_emails.compact.map(&:strip).uniq.join(',')
  end
end
