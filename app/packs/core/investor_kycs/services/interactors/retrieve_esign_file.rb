class RetrieveEsignFile
  include Interactor

  def call
    Rails.logger.debug "Interactor: RetriveEsignFile called"

    if context.adhaar_esign_id.present?
      adhaar_esign = AdhaarEsign.find(context.adhaar_esign_id)
      adhaar_esign.retrieve_signed
      context.adhaar_esign = adhaar_esign
    else
      Rails.logger.debug "No AdhaarEsign specified"
      context.fail!(message: "No AdhaarEsign specified")
    end
  end
end
