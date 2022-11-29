class OfferEsignProvider
  def initialize(offer)
    @offer = offer
  end

  def spa_file_name
    "SPA for #{@offer.user.full_name} : Offer #{@offer.id}"
  end

  # Called from OfferSpaGenerator.prepare_for_signature, after the SPA has been generated
  def generate_spa_signatures(force: false)
    user_ids = @offer.signatory_ids

    if user_ids.present?

      if force
        cleanup_prev
        doc = nil
      else
        doc = Document.where(entity_id: @offer.entity_id, owner: @offer, name: spa_file_name).first
      end

      if doc.blank?
        # Download the orignal generated SPA file & create a doc
        @offer.spa.download do |tempfile|
          doc = @offer.documents.create!(name: spa_file_name, entity_id: @offer.entity_id, download: true, file: tempfile, user_id: @offer.user_id)
        end
        # Setup this doc for esign by user_ids
        AdhaarEsign.new.init(doc.id, user_ids.join(","), @offer, "Signature required on SPA : #{@offer.entity.name}").sign
      else
        Rails.logger.debug { "Offer #{@offer.id} already generated SPA AdhaarEsign" }
      end
    end
  end

  def cleanup_prev
    # Check if we already ahve a document with spa_file_name
    doc = Document.where(entity_id: @offer.entity_id, owner: @offer, name: spa_file_name).first
    if doc.present?
      # If we force the regeneration, then delete the old document with spa_file_name
      AdhaarEsign.where(document_id: doc.id).each(&:destroy)
      doc.destroy
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
end
