class OfferEsignProvider
  def initialize(offer)
    @offer = offer
  end

  def spa_file_name
    "SPA for #{@offer.user.full_name} : Offer #{@offer.id}"
  end

  def generate_spa_signatures
    user_ids = []
    user_ids << @offer.user.id if @offer.seller_signature_types.include?("adhaar")
    user_ids << @offer.interest.user.id if @offer.interest.buyer_signature_types.include?("adhaar") && @offer.interest

    if user_ids.present?
      doc = Document.where(entity_id: @offer.entity_id, owner: @offer, name: spa_file_name).first
      if doc.blank?
        @offer.spa.download do |tempfile|
          doc = @offer.documents.create!(name: spa_file_name, entity_id: @offer.entity_id, download: true, file: tempfile, user_id: @offer.user_id)
        end
        ae = AdhaarEsign.new.init(doc.id, user_ids.join(","), @offer, "Acceptance of SPA")
        ae.sign
        @offer.esign_required = true
        @offer.esign_link = ae.esign_link(@offer.user.phone)
        @offer.save
      else
        Rails.logger.debug { "Offer #{@offer.id} already generated SPA AdhaarEsign" }
      end
    end
  end

  def signature_completed(signature_type, file)
    Rails.logger.debug { "Offer #{@offer.id} signature_completed #{signature_type}" }
    if signature_type == "adhaar"
      doc = Document.where(entity_id: @offer.entity_id, owner: @offer, name: spa_file_name).first
      doc.locked = true
      doc.orignal = true
      doc.file = File.open(file, "rb")
      doc.save
      @offer.final_agreement = true
      @offer.esign_completed = true
      @offer.save
    end
  end

  def sign_link(phone); end
end
