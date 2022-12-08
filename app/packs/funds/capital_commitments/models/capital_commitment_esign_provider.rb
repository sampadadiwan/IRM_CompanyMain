class CapitalCommitmentEsignProvider
  def initialize(capital_commitment)
    @capital_commitment = capital_commitment
  end

  def signature_link(user, document_id = nil)
    if document_id
      @capital_commitment.esigns.where(user_id: user.id, document_id:).not_completed
    else
      @capital_commitment.esigns.where(user_id: user.id).not_completed
    end
  end

  def agreement_file_name
    "Capital Commitment Agreement"
  end

  # Do not call this twice - it will trigger the esing process again. Its not idempotent
  # Called from CapitalCommitmentDocGenerator.trigger_signatures,
  # after the Capital Commitment Agreement has been generated
  def trigger_signatures
    Rails.logger.debug { "CapitalCommitmentEsignProvider: trigger_signatures for #{@capital_commitment.id}" }

    @capital_commitment.esign_required = true
    @capital_commitment.save

    # Cleanup prev try
    cleanup_prev

    # Generate the required esigns
    generate_esigns

    # Create the document to be passed for signing
    generated_docs = @capital_commitment.documents.where(owner_tag: "Generated")
    generated_docs.each do |fund_agreement|
      # Setup this doc for esign for this capital_commitment
      AdhaarEsign.create!(document_id: fund_agreement.id, owner: @capital_commitment).sign
    end

    Rails.logger.debug { "Skipping signatures as CapitalCommitment #{@capital_commitment.id} does not have generated documents" } if generated_docs.count.zero?
  end

  def signature_completed(signature_type, document_id, file)
    Rails.logger.debug { "CapitalCommitment #{@capital_commitment.id} signature_completed #{signature_type}" }
    if File.exist?(file)
      doc = Document.where(owner: @capital_commitment, id: document_id).first
      doc.locked = true
      doc.orignal = true
      doc.file = File.open(file, "rb")
      doc.owner_tag = "Signed"
      doc.save

      # Every document that is needed to be signed is signed, then this is complete
      if @capital_commitment.esigns.not_completed.count.zero?
        @capital_commitment.esign_completed
        @capital_commitment.save
      end
    end
  end

  # For each signatory - generate an esign row
  def generate_esigns
    @capital_commitment.signatory_ids.each do |signature_type, user_ids|
      user_ids.each do |user_id|
        @capital_commitment.documents.where(owner_tag: "Generated").each do |doc|
          Esign.create(entity_id: @capital_commitment.entity_id, user_id:,
                       signature_type:, owner: @capital_commitment, document_id: doc.id,
                       reason: "Signature required for Capital Commitment : #{@capital_commitment.entity.name}")
        end
      end
    end
  end

  def cleanup_prev
    @capital_commitment.esign_completed = false
    @capital_commitment.save
    @capital_commitment.esigns.each(&:destroy)
    @capital_commitment.adhaar_esigns.each(&:destroy)
    @capital_commitment.signature_workflows.each(&:destroy)
  end
end
