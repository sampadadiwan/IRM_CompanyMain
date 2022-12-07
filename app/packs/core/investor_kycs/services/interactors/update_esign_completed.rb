class UpdateEsignCompleted
  include Interactor

  def call
    Rails.logger.debug "Interactor: UpdateEsignOwner called"

    if context.adhaar_esign.present?
      adhaar_esign = context.adhaar_esign
      user_id = context.user_id
      adhaar_esign.owner.esigns.where(user_id:, document_id: adhaar_esign.document_id).update(completed: true)
    else
      Rails.logger.debug "No AdhaarEsign specified"
      context.fail!(message: "No AdhaarEsign specified")
    end
  end
end
