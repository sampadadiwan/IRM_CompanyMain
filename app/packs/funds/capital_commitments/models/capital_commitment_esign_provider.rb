class CapitalCommitmentEsignProvider
  def initialize(capital_commitment)
    @capital_commitment = capital_commitment
  end

  def signature_link(user)
    @capital_commitment.esigns.where(user_id: user.id).first&.link
  end

  def agreement_file_name
    "Capital Commitment Agreement"
  end

  # Do not call this twice - it will trigger the esing process again. Its not idempotent
  # Called from CapitalCommitmentDocGenerator.trigger_signatures,
  # after the Capital Commitment Agreement has been generated
  def trigger_signatures
    Rails.logger.debug { "CapitalCommitmentEsignProvider: trigger_signatures for #{@capital_commitment.id} #{force}" }

    @capital_commitment.esign_required = true
    @capital_commitment.save

    # Cleanup prev try
    cleanup_prev

    # Generate the required esigns
    generate_esigns

    # Create the document to be passed for signing
    fund_agreement = prepare_doc

    if fund_agreement.present?
      # Setup this doc for esign for this capital_commitment
      AdhaarEsign.create!(document_id: fund_agreement.id, owner: @capital_commitment).sign
    else
      Rails.logger.debug { "Skipping 2 as CapitalCommitment #{@capital_commitment.id} does not have #{agreement_file_name}" }
    end
  end

  def signature_completed(signature_type, file)
    Rails.logger.debug { "CapitalCommitment #{@capital_commitment.id} signature_completed #{signature_type}" }
    if File.exist?(file)
      doc = Document.where(entity_id: @capital_commitment.entity_id, owner: @capital_commitment, name: agreement_file_name).first
      doc.locked = true
      doc.orignal = true
      doc.file = File.open(file, "rb")
      doc.save

      @capital_commitment.esign_completed = true
      @capital_commitment.save
    end
  end

  private

  # For each signatory - generate an esign row
  def generate_esigns
    @capital_commitment.signatory_ids.each do |signature_type, user_ids|
      user_ids.each do |user_id|
        Esign.create(entity_id: @capital_commitment.entity_id, user_id:,
                     signature_type:, owner: @capital_commitment,
                     reason: "Signature required for Capital Commitment : #{@capital_commitment.entity.name}")
      end
    end
  end

  # If the Capital Commitment Agreement is present, clone it and use that file for signing
  def prepare_doc
    @capital_commitment.documents.where(name: agreement_file_name).first
  end

  def cleanup_prev
    @capital_commitment.adhaar_esign&.destroy
    @capital_commitment.esigns.each(&:destroy)
    @capital_commitment.signature_workflows.each(&:destroy)
  end
end
