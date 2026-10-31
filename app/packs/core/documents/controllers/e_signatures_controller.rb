class ESignaturesController < ApplicationController
  before_action :set_e_signature, only: %i[show edit update destroy]
  before_action :set_signing_e_signature, only: %i[sign]

  # GET /e_signatures or /e_signatures.json
  def index
    @bread_crumbs = { 'E-Signatures': e_signatures_path }
    @e_signatures = policy_scope(ESignature).order(:position)
  end

  # GET /e_signatures/1 or /e_signatures/1.json
  def show; end

  # GET /e_signatures/1/sign
  # Embedded eSigning: the page that hosts Digio's signing panel for this signer. Authorization is the
  # signer's identity (ESignaturePolicy#sign?), not entity membership; the state decides what the page
  # offers. Worked examples H2, E6, E9, E11, E12 — openspec/changes/embedded-esign-digio/design.md
  def sign
    @document = @e_signature.document
    @signing_state = @e_signature.signing_state
    @signer_place, @signer_total = @e_signature.signer_place
    @bread_crumbs = { "#{@document.name}": document_path(@document), Sign: nil }
  end

  # POST /e_signatures/1/sign_result
  # The signing page reports what Digio's panel said (completed, an error code, closed). It is a hint, never a
  # status: this action records it, maps it to a message, and at most asks for a status check with Digio.
  # No branch writes a status. Worked examples H4, E17, E18, E20, X1-X11 —
  # openspec/changes/embedded-esign-digio/design.md#worked-examples
  def sign_result
    e_signature = ESignature.find_by(id: params[:id])
    return refuse_sign_result unless e_signature

    authorize e_signature, :sign_result?
    event, error_code, txn_id = sign_result_params.values_at(:event, :error_code, :txn_id)
    return render(json: { message: DigioSdkErrors::OURS_MESSAGE, action: "none" }, status: :unprocessable_content) if event.blank?

    result = sign_result_for(event, error_code)
    record_sign_event(e_signature, result, event:, error_code:, txn_id:)
    DocumentEsignUpdateJob.perform_later(e_signature.document_id, current_user.id) if result.check
    notify_sign_problem(e_signature, event:, error_code:, txn_id:) if result.alert

    render json: { message: result.message, action: result.action }
  rescue Pundit::NotAuthorizedError
    refuse_sign_result
  end

  # GET /e_signatures/new
  def new
    @e_signature = ESignature.new(e_signature_params)
    # M26 — the firm always comes from the document, never from the request
    @e_signature.entity_id = @e_signature.document&.entity_id
    authorize @e_signature
    @bread_crumbs = { "#{@e_signature.document.name}": document_path(@e_signature.document), 'New eSignature': nil }
  end

  # GET /e_signatures/1/edit
  def edit
    @bread_crumbs[:Edit] = nil
  end

  # POST /e_signatures or /e_signatures.json
  def create
    @e_signature = ESignature.new(e_signature_params)
    # M26 — the firm always comes from the document, never from the request
    @e_signature.entity_id = @e_signature.document&.entity_id
    authorize @e_signature
    respond_to do |format|
      if @e_signature.save
        format.html { redirect_to e_signature_url(@e_signature), notice: "E signature was successfully created." }
        format.json { render :show, status: :created, location: @e_signature }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @e_signature.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /e_signatures/1 or /e_signatures/1.json
  def update
    respond_to do |format|
      # M26 — an update never moves the signer to another document (it was authorized on this one)
      if @e_signature.update(e_signature_params.except(:document_id))
        format.html { redirect_to e_signature_url(@e_signature), notice: "E signature was successfully updated." }
        format.json { render :show, status: :ok, location: @e_signature }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @e_signature.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /e_signatures/1 or /e_signatures/1.json
  def destroy
    @e_signature.destroy

    respond_to do |format|
      format.html { redirect_to e_signatures_url, notice: "E signature was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_e_signature
    @e_signature = ESignature.find(params[:id])
    authorize @e_signature
    @bread_crumbs = { "#{@e_signature.document.name}": document_path(@e_signature.document), eSignature: e_signature_path(@e_signature) }
  end

  # Everyone who cannot sign here gets the same refusal, so the page never says whether a signature
  # request, or a document, exists.
  def set_signing_e_signature
    @e_signature = ESignature.find_by(id: params[:id])
    if @e_signature.nil?
      skip_authorization
      redirect_to root_path, alert: DigioSdkErrors::NOT_AVAILABLE_MESSAGE
    else
      authorize @e_signature, :sign?
    end
  rescue Pundit::NotAuthorizedError
    redirect_to root_path, alert: DigioSdkErrors::NOT_AVAILABLE_MESSAGE
  end

  # What the signing page may tell us: three short strings, nothing that identifies a record.
  def sign_result_params
    params.slice(:event, :error_code, :txn_id).permit(:event, :error_code, :txn_id).to_h.transform_values { |v| v.to_s.first(100) }.symbolize_keys
  end

  # A browser-side pseudo-event, a completed signature, or one of Digio's error codes, in that order
  def sign_result_for(event, error_code)
    DigioSdkErrors.client_event(event) ||
      (DigioSdkErrors.completed?(event) ? DigioSdkErrors.completion : DigioSdkErrors.lookup(error_code))
  end

  # The audit entry never blocks the answer: a failure to write it is reported, not shown to the signer.
  def record_sign_event(e_signature, result, event:, error_code:, txn_id:)
    document = e_signature.document
    log = document.esign_log || EsignLog.create!(entity_id: document.entity_id, document:)
    log.append_event(:sdk_events, { at: Time.zone.now.iso8601, signer_email: e_signature.email, event:, error_code:, txn_id:, group: result.group })
  rescue StandardError => e
    ErrorReport.notify(e, source: "ESignaturesController sign_result", **ErrorReport.document_context(e_signature.document))
  end

  # A problem on our side or Digio's that the signer cannot fix: support hears about it, the signer gets a generic message.
  def notify_sign_problem(e_signature, event:, error_code:, txn_id:)
    ErrorReport.notify(StandardError.new("Embedded eSign reported #{error_code.presence || event} for #{e_signature.document.name}"),
                       source: "ESignaturesController sign_result", error_code:, txn_id:, signer_email: e_signature.email,
                       **ErrorReport.document_context(e_signature.document))
  end

  # Same refusal whether the request does not exist or belongs to someone else
  def refuse_sign_result
    skip_authorization
    render json: { message: DigioSdkErrors::NOT_AVAILABLE_MESSAGE, action: "none" }, status: :forbidden
  end

  # Only allow a list of trusted parameters through.
  # M26 — entity_id (taken from the document) and status (written by the e-sign provider callbacks)
  # are not accepted from the form (M26-X5)
  def e_signature_params
    params.require(:e_signature).permit(:user_id, :label, :signature_type, :document_id, :notes)
  end
end
