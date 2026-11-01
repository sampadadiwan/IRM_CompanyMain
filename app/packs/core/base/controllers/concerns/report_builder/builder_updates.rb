# One answer for every change made in the Report Builder page: the settings
# panel, the preview and the health badge, re-rendered together as Turbo
# Streams, plus a message — so the panel and the preview can never disagree and
# nothing reloads the page.
#
# A request counts as coming from the builder when it is a form inside the
# settings panel (Turbo sends `Turbo-Frame: report_builder_settings`) or a
# fetch from report_builder_controller.js (`X-Report-Builder: 1`). The guided
# wizard, the JSON API and anything else keep their redirects / JSON.
#
# Worked examples H2, E19 — openspec/changes/report-builder-live-builder/business-rules.md
module ReportBuilder
  module BuilderUpdates
    extend ActiveSupport::Concern

    private

    def builder_request?
      request.headers["Turbo-Frame"] == "report_builder_settings" || request.headers["X-Report-Builder"] == "1"
    end

    # A form on a wizard step names the step to go back to
    def wizard_request?
      params[:wizard_step].present? && ReportBuilder::Wizard::WIZARD_STEP_KEYS.include?(params[:wizard_step].to_s)
    end

    # Renders the three streams and a toast. `level` :success / :danger.
    def respond_with_builder_update(notice:, level: :success, undo_token: nil, status: :ok)
      @report.reload
      load_builder_state
      load_preview_state

      render status: status, turbo_stream: [
        turbo_stream.replace("report_builder_settings", partial: "report_builder/settings_panel"),
        turbo_stream.replace("report_builder_preview", partial: "report_builder/preview_table", locals: { builder: true }),
        turbo_stream.replace("report_builder_health", partial: "report_builder/health"),
        turbo_stream.append("report_builder_toasts", partial: "report_builder/toast",
                                                     locals: { message: notice, level: level, undo_token: undo_token })
      ]
    end

    # A builder change answers with streams, a wizard change returns to its
    # step with the message; anything else as before
    def finish_change(notice, fallback: nil, level: :success, undo_token: nil, status: :ok)
      return respond_with_builder_update(notice: notice, level: level, undo_token: undo_token, status: status) if builder_request?

      if wizard_request?
        flash_key = level == :danger ? :alert : :notice
        return redirect_to(wizard_report_builder_step_path(@report, step: params[:wizard_step]), flash_key => notice)
      end

      fallback ? fallback.call : redirect_back_or_to(edit_report_builder_path(@report))
    end
  end
end
