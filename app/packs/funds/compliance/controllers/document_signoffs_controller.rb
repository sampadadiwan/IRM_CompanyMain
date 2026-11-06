# ⑦ "Mark signed (wet ink)": the scan is signed on the entered date (H23, X27). Opened from a failing
# row of an IC-note result in the app's remote modal; answers with a Turbo stream (flash + row) or, for
# plain HTML, a redirect back.
class DocumentSignoffsController < ApplicationController
  # The Mark signed form, drawn in the remote modal
  def new
    document = policy_scope(Document).find_by(id: params[:document_id]) || raise(Pundit::NotAuthorizedError)
    @signoff = DocumentSignoff.new(entity_id: current_user.entity_id, document:, marked_by: current_user)
    authorize @signoff, :create?
  end

  def create
    document = policy_scope(Document).find_by(id: params.dig(:document_signoff, :document_id))
    raise Pundit::NotAuthorizedError if document.nil?

    @signoff = DocumentSignoff.new(entity_id: current_user.entity_id, document:, marked_by: current_user,
                                   signed_on: params.dig(:document_signoff, :signed_on))
    authorize @signoff
    saved = @signoff.save
    notice, alert = saved ? ["Marked signed on #{l(@signoff.signed_on)} — the next run counts it", nil] : [nil, @signoff.errors.full_messages.to_sentence]
    respond_to do |format|
      format.turbo_stream do
        @notice = notice
        @alert = alert
        render "document_signoffs/create"
      end
      format.html { redirect_back_or_to(compliance_home_path, notice:, alert:) }
    end
  end
end
