# The builder's Delivery tab: saving the email schedule (recipients checked,
# outsiders confirmed, time zone named), the check the tab runs before showing
# the outsider popup, and "Send test to me".
#
# The popup is a hint; the save is the guard — it re-checks the recipients with
# the same ReportScheduleRecipients, so a request that skips the popup is still
# refused (X4).
#
# Worked examples H4–H8, E3–E7, X2–X5 — openspec/changes/report-builder-delivery/business-rules.md
module ReportBuilder
  module Delivery
    extend ActiveSupport::Concern

    # What a new schedule is sent in, unless another zone is picked (E6 keeps an old one's own)
    DEFAULT_TIMEZONE = "Asia/Kolkata".freeze

    # PATCH /report_builder/:id/schedule
    def update_schedule
      authorize @report, :update?

      schedule = @report.report_schedule || @report.build_report_schedule

      # E5 — switching off saves at once; what's typed isn't checked
      if params[:enabled].to_s == "false"
        schedule.update!(enabled: false) if schedule.persisted?
        return schedule_answer("Schedule turned off")
      end

      # X2, X3 — every address must be an email, and there must be one
      recipients = ReportScheduleRecipients.new(params[:recipients], entity: schedule_entity)
      return schedule_refused(recipients.error, field_error: recipients.error) if recipients.error

      # X4 — people outside the company only once the popup was confirmed
      unconfirmed = recipients.outsiders.any? && params[:outsiders_ok].to_s != "1"
      return schedule_refused("Confirm sending to people outside #{schedule_entity.name} first") if unconfirmed

      # H4, H5, E4 — stored tidied, in the chosen (or kept) time zone
      if schedule.update(enabled: true, recipients: recipients.emails,
                         frequency: params[:frequency].presence || schedule.frequency || "daily",
                         timezone: schedule_timezone(schedule))
        people = helpers.pluralize(recipients.emails.size, "person")
        schedule_answer("Schedule saved — #{helpers.report_schedule_label(schedule)} to #{people}")
      else
        schedule_refused(schedule.errors.full_messages.to_sentence)
      end
    end

    # POST /report_builder/:id/schedule_check — what Save schedule asks before
    # saving: a field error, or the outsiders to confirm in the popup (H5, X2)
    def schedule_check
      authorize @report, :update?

      recipients = ReportScheduleRecipients.new(params[:recipients], entity: schedule_entity)
      outsiders  = recipients.error ? [] : recipients.outsiders
      draft      = ReportSchedule.new(frequency: params[:frequency].presence || "daily",
                                      timezone: schedule_timezone(@report.report_schedule || ReportSchedule.new))
      summary    = helpers.schedule_outsiders_summary(outsiders, schedule_entity, helpers.report_schedule_label(draft)) if outsiders.any?

      render json: { error: recipients.error, outsiders: outsiders, summary_html: summary }
    end

    # POST /report_builder/:id/schedule_test — the scheduled email, to the
    # signed-in user alone; "Last sent" is left as it is (H6, H8, X5)
    def schedule_test
      authorize @report, :update?

      ReportBuilderExportJob.perform_later(@report.id, current_user.id, nil, test_send: true)
      schedule_answer("A test is on its way to #{current_user.email}")
    end

    private

    # The company a scheduled run reads and sends as (fix-tenant-isolation R4)
    def schedule_entity
      @report.entity || current_user.entity
    end

    # A zone from the agent schedules' list; else the schedule's own; a new one IST (E6)
    def schedule_timezone(schedule)
      allowed = AgentSchedule::CURATED_TIMEZONES.map(&:first)
      params[:timezone].presence_in(allowed) || (schedule.persisted? ? schedule.timezone : DEFAULT_TIMEZONE)
    end

    def schedule_answer(notice)
      return respond_with_builder_update(notice: notice) if builder_request?

      render json: { ok: true, message: notice }
    end

    # Refused: the tab keeps what was typed and shows the field error (X2, X3)
    def schedule_refused(message, field_error: nil)
      if builder_request?
        @schedule_draft = { recipients: params[:recipients].to_s, frequency: params[:frequency].presence,
                            timezone: params[:timezone].presence, error: field_error }
        return respond_with_builder_update(notice: "Schedule wasn't saved — #{message}", level: :danger,
                                           status: :unprocessable_entity)
      end

      render json: { errors: [message] }, status: :unprocessable_entity
    end
  end
end
