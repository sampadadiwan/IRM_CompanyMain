# Settings → Document Checks: one page per record type, one card per document. Each card saves on its own
# (DocChecks::CardForm); presets add unsaved rows to the card; Try on a KYC starts a trial run.
# See openspec/changes/document-checks/design.md (card ① Setup). Worked examples H1, H2, H4, E1–E5, E16, X4.
class DocChecksController < ApplicationController
  before_action :set_record_type

  # GET /doc_checks
  def index
    authorize DocCheck
    @entry = DocChecks::Registry.for(@record_type)
    @cards = cards
    # A saved check whose field was removed from the form: banner + row message. Worked example E16.
    @missing_field_count = @cards.sum { |card| card.rows.count(&:field_missing?) }
    @bread_crumbs = { 'Document Checks': nil }
  end

  # GET /doc_checks/card?document_name= — one card's form (Cancel re-renders the saved state)
  def card
    authorize DocCheck
    render partial: "doc_checks/card", locals: { card: load_card(params[:document_name]) }
  end

  # PATCH /doc_checks/card — save one card. Worked examples H2, E3, X4.
  def update_card
    authorize DocCheck, :update_card?
    form = DocChecks::CardForm.new(entity: current_user.entity, record_type: @record_type,
                                   document_name: params[:document_name], rows: params[:rows] || [])
    if form.save
      render_card(load_card(form.document_name), notice: "Saved")
    else
      render_card(form, status: :unprocessable_content)
    end
  end

  # POST /doc_checks/preset — the card's current rows plus the preset's, unsaved. Worked examples H1, E4.
  def preset
    authorize DocCheck, :preset?
    form = DocChecks::CardForm.new(entity: current_user.entity, record_type: @record_type,
                                   document_name: params[:document_name], rows: params[:rows] || [])
    key = DocChecks::Presets.key_for(form.document_name)
    return render_card(form, status: :unprocessable_content) unless key

    applied = DocChecks::Presets.rows_for(entity: current_user.entity, document_name: form.document_name, key:,
                                          existing: form.rows, record_type: @record_type)
    form.rows.concat(applied.rows)
    render_card(form, not_added: applied.not_added, dirty: applied.rows.any?)
  end

  # POST /doc_checks/trial — a trial run on one record; nothing on it changes. Worked example H4.
  def trial
    authorize DocCheck, :trial?
    record = policy_scope(DocChecks::Registry.for(@record_type).record_class).find_by(id: params[:record_id])
    return redirect_to doc_checks_path(record_type: @record_type), alert: "KYC not found" unless record && DocChecks::Registry.for(record).can_view?(current_user, record)

    @run = DocChecks::StartRun.call(record:, user: current_user, trial: true)
    redirect_to doc_checks_path(record_type: @record_type, trial_run_id: @run.id)
  end

  private

  # Only registered record types — never constantize user input
  def set_record_type
    @record_type = params[:record_type].presence || "InvestorKyc"
    raise ActiveRecord::RecordNotFound unless DocChecks::Registry.supported?(@record_type)
  end

  # Cards with checks first, then the other documents. A check on a document no longer on the lists still
  # gets a card, so it can be deleted.
  def cards
    entity = current_user.entity
    names = DocChecks::Registry.for(@record_type).document_names(entity)
    saved = policy_scope(DocCheck).where(record_type: @record_type).ordered.group_by { |c| c.document_name.downcase }
    extra = saved.keys - names.map(&:downcase)
    all = names + extra.map { |key| saved[key].first.document_name }
    built = all.map { |name| DocChecks::CardForm.new(entity:, record_type: @record_type, document_name: name, rows: card_rows(saved[name.downcase])) }
    built.partition { |card| card.rows.any? }.flatten
  end

  def load_card(document_name)
    entity = current_user.entity
    rows = policy_scope(DocCheck).where(record_type: @record_type, document_name: document_name.to_s.squish).ordered
    DocChecks::CardForm.new(entity:, record_type: @record_type, document_name:, rows: card_rows(rows))
  end

  def card_rows(checks)
    Array(checks).map { |c| c.attributes.slice("id", *DocChecks::CardForm::ROW_ATTRIBUTES) }
  end

  def render_card(card, status: :ok, notice: nil, not_added: [], dirty: false)
    flash.now[:notice] = notice if notice
    render turbo_stream: turbo_stream.replace(helpers.doc_check_card_dom_id(card.document_name),
                                              partial: "doc_checks/card",
                                              locals: { card:, not_added:, dirty: dirty || status != :ok }),
           status:
  end
end
