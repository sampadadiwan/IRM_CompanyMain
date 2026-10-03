# Documents needing attention (the entity-wide list) and resolving an item on the spot: Use document value,
# Mark as OK (with a reason) and Undo. Every resolution re-assesses the record, moves its journey and
# refreshes its tab.
# See openspec/changes/document-checks/design.md (cards ⑦ Results and ⑧ Screens). Worked examples H5, H6, H9, E19, X6, X8.
class DocCheckResultsController < ApplicationController
  before_action :set_result, only: %i[use_document_value mark_ok undo]

  # GET /doc_check_results
  def index
    authorize DocCheckResult
    scope = policy_scope(DocCheckResult).joins(:doc_check_run).where(doc_check_runs: { current: true, trial: false })
    scope = filter(scope)
    @reason = params[:reason].presence
    ordered = scope.includes(doc_check_run: :record).order("doc_check_runs.finished_at DESC, doc_check_results.id")
    if @reason == "document_changed"
      # "Document changed" is derived (the document's current file vs the one read), so it can't be a
      # query: filter every current result first, then paginate — never a sparse page
      changed = changed_results(ordered)
      @pagy = Pagy.new(count: changed.size, page: params[:page] || 1, limit: 50)
      @results = changed[@pagy.offset, @pagy.limit] || []
    else
      @pagy, @results = pagy(ordered, limit: 50)
      @assessments = assessments_for(@results)
    end
    @bread_crumbs = { 'Documents needing attention': nil }
  end

  # PATCH /doc_check_results/:id/use_document_value. Worked example H5.
  def use_document_value
    @result.use_document_value!(user: current_user)
    after_resolution
  rescue ActiveRecord::RecordInvalid
    after_resolution(errors: { @result.id => @result.errors.full_messages.to_sentence })
  end

  # PATCH /doc_check_results/:id/mark_ok — reason required. Worked examples H6, X8.
  def mark_ok
    @result.mark_ok!(user: current_user, reason: params[:reason])
    after_resolution
  rescue ActiveRecord::RecordInvalid
    after_resolution(errors: { @result.id => @result.errors[:resolve_reason].first || @result.errors.full_messages.to_sentence },
                     status: :unprocessable_content)
  end

  # PATCH /doc_check_results/:id/undo. Worked example E19.
  def undo
    @result.undo!
    after_resolution
  rescue ActiveRecord::RecordInvalid
    after_resolution
  end

  # POST /doc_check_results/check_again — record_type, record_ids[]. Worked example H9.
  def check_again
    authorize DocCheckResult
    record_type = params[:record_type].presence || "InvestorKyc"
    raise ActiveRecord::RecordNotFound unless DocChecks::Registry.supported?(record_type)

    entry = DocChecks::Registry.for(record_type)
    records = entry.record_class.where(entity_id: current_user.entity_id, id: Array(params[:record_ids]))
    queued = records.count do |record|
      next false unless entry.can_edit?(current_user, record)

      DocChecks::StartRun.call(record:, user: current_user, trigger: "again")
      true
    rescue DocChecks::Error::AlreadyRunning
      false
    end
    redirect_to doc_check_results_path(reason: params[:reason]),
                notice: I18n.t("doc_checks.run.queued", count: queued, record_label: entry.record_label)
  end

  private

  def set_result
    @result = policy_scope(DocCheckResult).find(params[:id])
    authorize @result, :resolve?
  end

  # The record's journey and tab follow every resolution
  def after_resolution(errors: {}, status: :ok)
    record = @result.doc_check_run.record.reload
    assessment = DocChecks::Assessment.new(record)
    # A refused resolution changed nothing: no journey move, and no broadcast — the broadcast would reload
    # this user's own tab and morph away the error shown below (Worked example X8)
    if errors.empty?
      DocChecks::Registry.for(record).on_assessed(record, assessment.settled?)
      record.journey_progress!(actor: current_user) if record.respond_to?(:journey_progress!)
      DocChecks::Broadcast.record(record)
    end
    render turbo_stream: turbo_stream.replace(DocChecks::Broadcast.panel_frame_id(record), partial: "doc_check_runs/panel",
                                                                                           locals: { record:, assessment:, errors: }),
           status:
  end

  # Reason, document and checked-date filters
  def filter(scope)
    if (outcomes = DocCheckResult::REASONS[params[:reason]])
      scope = scope.where(outcome: outcomes, resolution: nil)
    elsif params[:reason] != "document_changed"
      scope = scope.needing_attention
    end
    scope = scope.where(document_name: params[:document_name]) if params[:document_name].present?
    scope = scope.where(doc_check_runs: { finished_at: parse_date(params[:checked_from]).beginning_of_day.. }) if parse_date(params[:checked_from])
    scope = scope.where(doc_check_runs: { finished_at: ..parse_date(params[:checked_to]).end_of_day }) if parse_date(params[:checked_to])
    scope
  end

  def parse_date(value)
    Date.parse(value.to_s) if value.present?
  rescue Date::Error
    nil
  end

  # One Assessment per record shown (3 small queries each), keyed by run
  def assessments_for(results)
    results.map(&:doc_check_run).uniq.to_h { |run| [run.id, DocChecks::Assessment.new(run.record)] }
  end

  # Every current result whose document changed after its run, in list order. Walks the entity's current
  # runs once (bounded by its record count) — only when this filter is chosen.
  def changed_results(ordered)
    @assessments = {}
    ordered.to_a.select do |result|
      @assessments[result.doc_check_run_id] ||= DocChecks::Assessment.new(result.doc_check_run.record)
      changed?(result)
    end
  end

  def changed?(result)
    assessment = @assessments[result.doc_check_run_id]
    assessment&.groups&.find { |g| g.name.casecmp?(result.document_name) }&.changed
  end
  helper_method :changed?
end
