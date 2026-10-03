# Settings → Document Checks: one page per record type. It reads as a summary — a tile per document saying
# what its checks do — and each document is edited in its own side panel (DocChecks::CardForm). Suggested
# checks for every document are reviewed and added in one go; Test on a KYC starts a trial run.
# See openspec/changes/document-checks/design.md (card ① Setup). Worked examples H1, H2, H4, E1–E5, E16, X4.
class DocChecksController < ApplicationController
  before_action :set_record_type

  # GET /doc_checks — the setup page; .xlsx is its Export, in the columns ImportDocCheck reads back
  # (Worked example H14)
  def index
    authorize DocCheck
    respond_to do |format|
      format.html { load_page }
      format.xlsx do
        @doc_checks = policy_scope(DocCheck).where(record_type: @record_type).order(:document_name, :position, :id)
        @field_labels = DocChecks::Registry.for(@record_type).fields_for(current_user.entity).to_h { |f| [f.name, f.label] }
        response.headers["Content-Disposition"] = %(attachment; filename="doc_checks.xlsx")
      end
    end
  end

  # PATCH /doc_checks/save_document — one document's checks, from its side panel. Nothing is saved if a row
  # is wrong: the page comes back with that panel open and the row errors shown. Worked examples H2, E3.
  def save_document
    authorize DocCheck, :save_document?
    form = DocChecks::CardForm.new(entity: current_user.entity, record_type: @record_type,
                                   document_name: params[:document_name], rows: params[:rows] || {})
    if form.save
      redirect_to doc_checks_path(record_type: @record_type), notice: "#{form.document_name}: checks saved"
    else
      load_page(form:)
      @open_panel = helpers.doc_check_card_dom_id(form.document_name)
      flash.now[:alert] = "#{form.document_name}: some checks need fixing — see the marked rows"
      render :index, status: :unprocessable_content
    end
  end

  # POST /doc_checks/add_recommended — the ticked suggestions, in one go. Worked examples H1, E4.
  def add_recommended
    authorize DocCheck, :add_recommended?
    added = DocChecks::Presets.add_recommended(entity: current_user.entity, record_type: @record_type, picks: params[:picks])
    notice = added.zero? ? "No checks were added" : "Added #{added} #{'check'.pluralize(added)}"
    redirect_to doc_checks_path(record_type: @record_type), notice:
  end

  # POST /doc_checks/trial — a trial run on one record; nothing on it changes. Worked example H4.
  def trial
    authorize DocCheck, :trial?
    record = policy_scope(DocChecks::Registry.for(@record_type).record_class).find_by(id: params[:record_id])
    return redirect_to doc_checks_path(record_type: @record_type), alert: "Pick a KYC to test the checks on" unless record && DocChecks::Registry.for(record).can_view?(current_user, record)

    @run = DocChecks::StartRun.call(record:, user: current_user, trial: true)
    redirect_to doc_checks_path(record_type: @record_type, trial_run_id: @run.id)
  end

  private

  # Only registered record types — never constantize user input
  def set_record_type
    @record_type = params[:record_type].presence || "InvestorKyc"
    raise ActiveRecord::RecordNotFound unless DocChecks::Registry.supported?(@record_type)
  end

  # Suggestions still to add, and every document (from a refused save, the posted rows with their errors)
  def load_page(form: nil)
    entity = current_user.entity
    @recommendations = DocChecks::Presets.recommendations(entity:, record_type: @record_type)
    @cards = cards(entity, form)
    # A saved check whose field was removed from the form: banner + row message. Worked example E16.
    @missing_field_count = @cards.sum { |card| card.rows.count(&:field_missing?) }
    @bread_crumbs = { 'Document Checks': nil }
  end

  # Documents with checks first, then the others. A check on a document no longer on the lists still gets a
  # tile, so it can be deleted.
  def cards(entity, form)
    names = DocChecks::Registry.for(@record_type).document_names(entity)
    saved = policy_scope(DocCheck).where(record_type: @record_type).ordered.group_by { |c| c.document_name.downcase }
    extra = saved.keys - names.map(&:downcase)
    all = names + extra.map { |key| saved[key].first.document_name }
    built = all.map do |name|
      next form if form&.document_name&.casecmp?(name)

      DocChecks::CardForm.new(entity:, record_type: @record_type, document_name: name, rows: card_rows(saved[name.downcase]))
    end
    built.partition { |card| card.rows.any? }.flatten
  end

  def card_rows(checks)
    Array(checks).map { |c| c.attributes.slice("id", *DocChecks::CardForm::ROW_ATTRIBUTES) }
  end
end
