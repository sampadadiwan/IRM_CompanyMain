class EoiEsignProvider
  def initialize(expression_of_interest)
    @expression_of_interest = expression_of_interest
  end

  def signature_link(user, document_id = nil)
    if document_id
      @expression_of_interest.esigns.where(user_id: user.id, document_id:).not_completed
    else
      @expression_of_interest.esigns.where(user_id: user.id).not_completed
    end
  end

  # Do not call this twice - it will trigger the esing process again. Its not idempotent
  # Called from EoiDocGenerator.trigger_signatures,
  # after the Capital Commitment Agreement has been generated
  def trigger_signatures
    Rails.logger.debug { "ExpressionOfInterestEsignProvider: trigger_signatures for #{@expression_of_interest.id}" }

    @expression_of_interest.esign_required = true
    @expression_of_interest.save

    # Cleanup prev try
    cleanup_prev

    # Generate the required esigns
    generate_esigns

    # Create the document to be passed for signing
    generated_docs = @expression_of_interest.documents.where(owner_tag: "Generated")
    generated_docs.each do |investment_opportunity_agreement|
      # Setup this doc for esign for this expression_of_interest
      AdhaarEsign.create!(document_id: investment_opportunity_agreement.id, owner: @expression_of_interest).sign
    end

    Rails.logger.debug { "Skipping signatures as ExpressionOfInterest #{@expression_of_interest.id} does not have generated documents" } if generated_docs.count.zero?
  end

  def signature_completed(signature_type, document_id, file)
    Rails.logger.debug { "ExpressionOfInterest #{@expression_of_interest.id} signature_completed #{signature_type}" }
    if File.exist?(file)
      doc = Document.where(owner: @expression_of_interest, id: document_id).first
      doc.locked = true
      doc.orignal = true
      doc.file = File.open(file, "rb")
      doc.owner_tag = "Signed"
      doc.save

      # Every document that is needed to be signed is signed, then this is complete
      if @expression_of_interest.esigns.not_completed.count.zero?
        @expression_of_interest.esign_completed = true
        @expression_of_interest.save
      end
    end
  end

  # For each signatory - generate an esign row
  def generate_esigns
    @expression_of_interest.signatory_ids.each do |signature_type, user_ids|
      user_ids.each do |user_id|
        @expression_of_interest.documents.where(owner_tag: "Generated").each do |doc|
          Esign.create(entity_id: @expression_of_interest.entity_id, user_id:,
                       signature_type:, owner: @expression_of_interest, document_id: doc.id,
                       reason: "Signature required for Capital Commitment : #{@expression_of_interest.entity.name}")
        end
      end
    end
  end

  def cleanup_prev
    @expression_of_interest.esign_completed = false
    @expression_of_interest.save
    @expression_of_interest.esigns.each(&:destroy)
    @expression_of_interest.adhaar_esigns.each(&:destroy)
    @expression_of_interest.signature_workflows.each(&:destroy)
  end
end
