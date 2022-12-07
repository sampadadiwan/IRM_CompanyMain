class UpdateEsignOwner
  include Interactor

  def call
    Rails.logger.debug "Interactor: UpdateEsignOwner called"

    if context.adhaar_esign.present?
      adhaar_esign = context.adhaar_esign
      if adhaar_esign.owner.respond_to?(:signature_completed)
        # Callback to the owner that the signed doc is now awailable
        adhaar_esign.owner.signature_completed("adhaar", adhaar_esign.document_id, adhaar_esign.download_file_name)
      end
    else
      Rails.logger.debug "UpdateEsignOwner: No AdhaarEsign specified"
      context.fail!(message: "UpdateEsignOwner: No AdhaarEsign specified")
    end
  end
end
