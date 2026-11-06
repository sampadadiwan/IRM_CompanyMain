# ⑦/⑧ Facts to confirm: the list of documents whose facts wait for a person, one document's facts with
# quote and page, confirm/correct, enter by hand, and Read now. Every record is loaded through the
# policy scope first and then authorized (design › Security item 1); documents through Document's scope.
# Worked examples H40, H43, H45, E67, X45, X46, X48 — openspec/changes/fund-compliance-monitoring/business-rules.md
class DocumentFactsController < ApplicationController
  LIST_LIMIT = 200

  def index
    authorize DocumentReading
    current_ids = policy_scope(DocumentReading).group(:document_id, :input_key).maximum(:id).values
    readings = policy_scope(DocumentReading).where(id: current_ids).includes(:document, :document_facts).order(id: :desc).limit(LIST_LIMIT)
    # Only documents this user may open (fund and document access still apply)
    @readings = readings.select { |r| policy(r).show? }
                        .select { |r| r.status != "manual" && (r.waiting? || r.status == "failed" || r.unconfirmed_count.positive?) }
  end

  def show
    @reading = policy_scope(DocumentReading).includes(:document, :document_facts).find_by(id: params[:id]) || raise(Pundit::NotAuthorizedError)
    authorize @reading
    @input = ComplianceDocumentInputs.find(current_user.entity, @reading.input_key)
  end

  # H43 / X45: the manual-entry form for a document and input
  def new
    @reading = build_reading
    authorize @reading, :manual?
    @input = ComplianceDocumentInputs.find(current_user.entity, @reading.input_key)
    raise Pundit::NotAuthorizedError if @input.nil?
  end

  # E66 / E67: confirm as read, or with corrected values
  def confirm
    reading = policy_scope(DocumentReading).find_by(id: params[:id]) || raise(Pundit::NotAuthorizedError)
    authorize reading, :confirm?
    result = DocumentFactConfirm.call(reading:, user: current_user, values: fact_values(reading.document_facts.map(&:fact_key)))
    redirect_to document_reading_path(reading), **(result.error ? { alert: result.error } : { notice: result.notice })
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

  # Only the keys of the facts in question; names lists arrive comma-separated
  def fact_values(keys)
    params.fetch(:values, {}).permit(*keys).to_h
  end
end
