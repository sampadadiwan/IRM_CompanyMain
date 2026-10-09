module KpiReportsHelper
  # The "Immediate Actions" cards (custom/action_summary_modal.scss) for a confirm popup on the KPI report
  # page: cards are [tint, icon, title, description]. Built with tag/safe_join so names are escaped —
  # the confirm modal inserts data-msg as HTML.
  def kpi_report_action_summary(cards, intro_action:)
    intro = tag.div(class: "action-summary__intro") do
      tag.div("Immediate Actions", class: "fw-bold text-dark") +
        tag.div(safe_join(["The following will happen when you click", " ", tag.strong(intro_action), ":"]), class: "text-muted")
    end
    items = cards.map do |tint, icon, title, desc|
      tag.div(class: "action-summary__item action-summary__item--#{tint}") do
        tag.span(tag.i(class: "ti #{icon}"), class: "action-summary__icon") +
          tag.div(tag.div(title, class: "action-summary__title") + tag.div(desc, class: "action-summary__desc"))
      end
    end
    intro + tag.div(safe_join(items), class: "action-summary__list")
  end

  # Send upload request's popup: who gets the magic link, that this report (not a new one) is used, and
  # where the step bar goes next. Worked examples H18 — openspec/changes/kpi-report-journey/design.md#worked-examples
  def send_request_action_summary(kpi_report, portal_users)
    kpi_report_action_summary([
                                ["blue", "ti-mail", "Upload link emailed",
                                 "#{pluralize(portal_users, 'portal user')} of #{kpi_report.for_name} get a magic link to upload KPIs"],
                                ["green", "ti-file-check", "This report is used",
                                 "#{kpi_report.period} ending #{l(kpi_report.as_of)} — no new report is created"],
                                ["purple", "ti-route", "Link Sent", "The report is marked Link Sent; the portfolio company uploads and submits next"]
                              ], intro_action: "Send upload request")
  end

  # Close report's popup: how many pending KPIs of the portfolio company will be approved, then closing.
  # Worked examples H5 — openspec/changes/kpi-report-journey/design.md#worked-examples
  def close_report_action_summary(kpi_report)
    pending = KpiReportClose.pending_scope(kpi_report)
    count = pending.count
    periods = pending.distinct.count(:kpi_report_id)
    approve = if count.zero?
                "Nothing is pending"
              else
                "#{pluralize(count, 'KPI')} across #{pluralize(periods, 'period')} for #{kpi_report.for_name}"
              end
    kpi_report_action_summary([
                                ["green", "ti-checks", "Approve pending KPIs", approve],
                                ["blue", "ti-lock", "Mark reviewed", "#{l(kpi_report.as_of)} is closed"]
                              ], intro_action: "Close report")
  end

  # Send completion email's popup: who will be emailed. Worked examples H8 — same design.
  def completion_email_action_summary(kpi_report)
    instance = kpi_report.current_workflow_instance
    step = instance&.snapshot_steps&.find { |s| s[:check_key] == KpiReportCompletionEmail::CHECK_KEY }
    recipients = step ? WorkflowAutoReminderJob.owners_for(instance, step, use: :actors) : []
    who = recipients.any? ? recipients.map(&:full_name).to_sentence : "Nobody — set Managed by or the step's actors"
    kpi_report_action_summary([
                                ["purple", "ti-mail", "Email", who],
                                ["grey", "ti-building", "Not the portfolio company", "Only your team is emailed"]
                              ], intro_action: "Send completion email")
  end
end
