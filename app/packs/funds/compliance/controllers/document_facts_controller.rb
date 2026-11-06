# ⑦/⑧ Facts to confirm: the list of documents whose facts wait for a person, one document's facts with
# quote and page, confirm/correct, enter by hand, and Read now. Every record is loaded through the
# policy scope first and then authorized (design › Security item 1); documents through Document's scope.
# Worked examples H40, H43, H45, E67, X45, X46, X48 — openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md
class DocumentFactsController < ApplicationController
  include ComplianceCrumbs

  LIST_LIMIT = 200

  def index
    authorize DocumentReading
    @q = DocumentReading.ransack(params[:q])
    # The newest reading per document and input, limited to documents this user may open (fund and
    # document access still apply) and to readings that still need a person
    current_ids = policy_scope(DocumentReading).group(:document_id, :input_key).maximum(:id).values
    candidates = policy_scope(DocumentReading).where(id: current_ids).includes(:document, :document_facts).order(id: :desc).limit(LIST_LIMIT)
    visible_ids = candidates.select { |r| policy(r).show? }
                            .select { |r| r.status != "manual" && (r.waiting? || r.status == "failed" || r.unconfirmed_count.positive?) }
                            .map(&:id)
    scope = @q.result.where(id: visible_ids).includes(:document, :document_facts)
    scope = search(scope, params.dig(:search, :value))
    @stats_scope = DocumentReading.where(id: scope.select(:id)).includes(:document_facts)
    scope = scope.order(id: :desc) if params.dig(:q, :s).blank?
    @pagy, @readings = pagy(scope, limit: params[:per_page] || 10)
    compliance_crumbs(["Facts to confirm", nil])
    # The Compliance hub's lazy Facts pane (R170): this page's content inside the hub frame
    return render_hub_pane(:facts, "document_facts/index") if hub_frame_request?(:facts)

    respond_to do |format|
      format.html
      format.turbo_stream { render partial: "document_facts/index", locals: { readings: @readings } }
    end
  end

  def show
    @reading = policy_scope(DocumentReading).includes(:document, :document_facts).find_by(id: params[:id]) || raise(Pundit::NotAuthorizedError)
    authorize @reading
    @input = ComplianceDocumentInputs.find(current_user.entity, @reading.input_key)
    compliance_crumbs(["Facts to confirm", document_readings_path], [@reading.document.name, nil])
  end

  # H43 / X45: the manual-entry form for a document and input
  def new
    @reading = build_reading
    authorize @reading, :manual?
    @input = ComplianceDocumentInputs.find(current_user.entity, @reading.input_key)
    raise Pundit::NotAuthorizedError if @input.nil?

    compliance_crumbs(["Facts to confirm", document_readings_path], ["Enter facts — #{@reading.document.name}", nil])
  end

  # E66 / E67: confirm as read, or with corrected values
  def confirm
    reading = policy_scope(DocumentReading).find_by(id: params[:id]) || raise(Pundit::NotAuthorizedError)
    authorize reading, :confirm?
    result = DocumentFactConfirm.call(reading:, user: current_user, values: fact_values(reading.document_facts.map(&:fact_key)))
    notice, alert = result.error ? [nil, result.error] : [result.notice, nil]
    respond_to do |format|
      # Replace the facts card in place and show the flash (E140)
      format.turbo_stream do
        @reading = reading.reload
        @input = ComplianceDocumentInputs.find(current_user.entity, @reading.input_key)
        @notice = notice
        @alert = alert
        render "document_facts/confirm"
      end
      format.html { redirect_to document_reading_path(reading), notice:, alert: }
    end
  end

  # H43: facts entered by hand (nothing sent to AI)
  def manual
    reading = build_reading
    authorize reading, :manual?
    input = ComplianceDocumentInputs.find(current_user.entity, reading.input_key)
    keys = input ? input.fact_keys : []
    result = DocumentFactConfirm.manual(document: reading.document, input_key: reading.input_key, user: current_user, values: fact_values(keys))
    if result.error
      redirect_to new_document_reading_path(document_id: reading.document_id, input_key: reading.input_key), alert: result.error
    else
      redirect_to document_reading_path(result.reading), notice: result.notice
    end
  end

  # H45 / X46: read an older document now, or retry a failed read
  def read_now
    reading = build_reading
    authorize reading, :read_now?
    result = DocumentReadingQueue.read_now(reading.document, reading.input_key)
    if result.error
      redirect_back_or_to(document_readings_path, alert: result.error)
    else
      redirect_to document_reading_path(result.reading), notice: "Queued for reading"
    end
  end

  private

  # A reading to authorize against: the document comes from Document's own scope (never a bare find)
  def build_reading
    document = policy_scope(Document).find_by(id: params[:document_id]) || raise(Pundit::NotAuthorizedError)
    DocumentReading.new(entity_id: current_user.entity_id, document:, input_key: params[:input_key].to_s)
  end

  # Search box: document name or input
  def search(scope, value)
    return scope if value.blank?

    like = "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s.strip)}%"
    scope.joins(:document).where("documents.name LIKE :like OR document_readings.input_key LIKE :like", like:)
  end

  # Only the keys of the facts in question; names lists arrive comma-separated
  def fact_values(keys)
    params.fetch(:values, {}).permit(*keys).to_h
  end
end
