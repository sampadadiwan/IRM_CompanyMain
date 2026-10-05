# Starting a check of a record's documents ("Check documents", "Check again", "Try again"), the record's
# Document checks tab (panel — the frame each browser re-fetches after a broadcast), and a trial run's
# results on the setup page (show).
# See openspec/changes/document-checks/design.md (cards ③ Triggers and ⑧ Screens). Worked examples H3, H4, E14, X7, X10.
class DocCheckRunsController < ApplicationController
  # POST /doc_check_runs — record_type, record_id
  def create
    record = find_record
    authorize record, :create?, policy_class: DocCheckRunPolicy
    DocChecks::StartRun.call(record:, user: current_user, trigger: params[:trigger].presence_in(%w[manual again]) || "manual")
    respond_after_start(record, notice: I18n.t("doc_checks.run.started", record: record.to_s))
  rescue DocChecks::Error::AlreadyRunning => e
    respond_after_start(record, alert: e.message)
  end

  # GET /doc_check_runs/panel — record_type, record_id: the record's Document checks tab
  def panel
    record = find_record
    authorize record, :panel?, policy_class: DocCheckRunPolicy
    render partial: "doc_check_runs/panel", locals: { record:, assessment: DocChecks::Assessment.new(record) }
  end

  # GET /doc_check_runs/:id — a trial run's results (the setup page's trial frame)
  def show
    @run = policy_scope(DocCheckRun, policy_scope_class: DocCheckRunPolicy::Scope).find(params[:id])
    authorize @run, :show?, policy_class: DocCheckRunPolicy
    render partial: "doc_check_runs/trial", locals: { run: @run }
  end

  private

  # Only registered record types, only the user's own entity
  def find_record
    record_type = params[:record_type].to_s
    raise ActiveRecord::RecordNotFound unless DocChecks::Registry.supported?(record_type)

    entry = DocChecks::Registry.for(record_type)
    entry.record_class.where(entity_id: current_user.entity_id).find(params[:record_id])
  end

  def respond_after_start(record, notice: nil, alert: nil)
    respond_to do |format|
      format.turbo_stream do
        flash.now[:notice] = notice if notice
        flash.now[:alert] = alert if alert
        render turbo_stream: turbo_stream.replace(DocChecks::Broadcast.panel_frame_id(record),
                                                  partial: "doc_check_runs/panel",
                                                  locals: { record:, assessment: DocChecks::Assessment.new(record), message: alert })
      end
      format.html do
        redirect_back_or_to DocChecks::Registry.for(record).show_path(record), notice:, alert:
      end
    end
  end
end
