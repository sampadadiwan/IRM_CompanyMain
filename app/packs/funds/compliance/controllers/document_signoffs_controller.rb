# ⑦ "Mark signed (wet ink)": the scan is signed on the entered date (H23, X27).
class DocumentSignoffsController < ApplicationController
  def create
    document = policy_scope(Document).find_by(id: params.dig(:document_signoff, :document_id))
    raise Pundit::NotAuthorizedError if document.nil?

    signoff = DocumentSignoff.new(entity_id: current_user.entity_id, document:, marked_by: current_user,
                                  signed_on: params.dig(:document_signoff, :signed_on))
    authorize signoff
    if signoff.save
      redirect_back_or_to(compliance_home_path, notice: "Marked signed on #{l(signoff.signed_on)}")
    else
      redirect_back_or_to(compliance_home_path, alert: signoff.errors.full_messages.to_sentence)
    end
  end
end
