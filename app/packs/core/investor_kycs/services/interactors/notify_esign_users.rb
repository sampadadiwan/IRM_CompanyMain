class NotifyEsignUsers
  include Interactor

  def call
    Rails.logger.debug "Interactor: NotifyEsignUsers called"

    if context.adhaar_esign.present?
      adhaar_esign = context.adhaar_esign
      user_id = context.user_id

      if user_id
        swf = SignatureWorkflow.where(entity_id: adhaar_esign.entity_id, owner: adhaar_esign.owner).last
        swf.mark_completed(user_id)
      end

    else
      Rails.logger.debug "No AdhaarEsign specified"
      context.fail!(message: "No AdhaarEsign specified")
    end
  end
end
