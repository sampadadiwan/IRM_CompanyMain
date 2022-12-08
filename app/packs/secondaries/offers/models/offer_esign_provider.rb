class OfferEsignProvider
  def initialize(offer)
    @offer = offer
  end

  def signature_link(user)
    @offer.esigns.where(user_id: user.id).not_completed
  end

  # Called from OfferSpaGenerator.trigger_signatures, after the SPA has been generated
  def trigger_signatures
    @offer.esign_required = true
    @offer.save

    # Cleanup prev try
    cleanup_prev

    # Create the document to be passed for signing
    spa_doc = prepare_doc

    # Generate the required esigns
    generate_esigns(spa_doc)

    if spa_doc.present?
      # Setup this doc for esign by user_ids
      AdhaarEsign.create!(document_id: spa_doc.id, owner: @offer).sign
    else
      Rails.logger.debug { "Skipping as Offer #{@offer.id} does not have #{spa_file_name}" }
    end
  end

  def prepare_doc
    doc = nil
    # Download the orignal generated SPA file & create a doc
    if @offer.spa.present?
      @offer.spa.download do |tempfile|
        doc = @offer.documents.create!(name: spa_file_name, entity_id: @offer.entity_id, download: true, file: tempfile, user_id: @offer.user_id)
      end
    end

    doc
  end

  def signature_completed(signature_type, document_id, file)
    Rails.logger.debug { "Offer #{@offer.id} signature_completed #{signature_type}" }
    if signature_type == "adhaar"
      if File.exist?(file)
        # For multi party signatures, the file may not yet be ready till the other parties have signed
        doc = Document.where(owner: @offer, id: document_id).first
        doc.locked = true
        doc.orignal = true
        doc.file = File.open(file, "rb")
        doc.owner_tag = "Signed"
        doc.save
        @offer.esign_completed = true
      end
      @offer.final_agreement = true
      @offer.save!
    end
  end

  # For each signatory - generate an esign row
  def generate_esigns(spa_doc)
    @offer.signatory_ids.each do |signature_type, user_ids|
      user_ids.each do |user_id|
        Esign.create(entity_id: @offer.entity_id, user_id:,
                     signature_type:, owner: @offer, document_id: spa_doc.id,
                     reason: "Signature required for SPA : #{@offer.entity.name}")
      end
    end
  end

  def spa_file_name
    "SPA for #{@offer.user.full_name} : Offer #{@offer.id}"
  end

  def cleanup_prev
    # Check if we already have a document with spa_file_name
    Document.where(entity_id: @offer.entity_id, owner: @offer, name: spa_file_name).each(&:destroy)
    @offer.esigns.each(&:destroy)
    @offer.adhaar_esigns.each(&:destroy)
    @offer.signature_workflows.each(&:destroy)
  end
end
