class CapitalCommitmentEsignProvider
  def initialize(capital_commitment)
    @capital_commitment = capital_commitment
  end

  def agreement_file_name
    "Capital Commitment Agreement"
  end

  def signed_file_name
    "Signed: Capital Commitment Agreement"
  end

  # Called from CapitalCommitmentDocGenerator.prepare_for_signature, after the SPA has been generated
  def generate_doc_signatures(force: false)
    user_ids = @capital_commitment.signatory_ids
    Rails.logger.debug { "CapitalCommitmentDocGenerator: generate_doc_signatures #{user_ids}, #{force}" }
    if user_ids.present?

      cleanup_prev if force

      doc = Document.where(entity_id: @capital_commitment.entity_id, owner: @capital_commitment, name: agreement_file_name).first

      if doc.present?
        # Download the orignal generated SPA file & create a doc
        doc.download do |tempfile|
          doc = @capital_commitment.documents.create!(name: signed_file_name, entity_id: @capital_commitment.entity_id, download: true, file: tempfile, user_id: @capital_commitment.user_id)
        end
        # Setup this doc for esign by user_ids
        ae = AdhaarEsign.new.init(doc.id, user_ids.join(","), @capital_commitment, "Signature for #{agreement_file_name}")
        if ae.sign
          # Mark the capital_commitment with the esign link
          @capital_commitment.esign_required = true
          @capital_commitment.esign_link = ae.esign_link
          @capital_commitment.save
          # Setup a workflow to chase and track the signatories
          SignatureWorkflow.create!(owner: @capital_commitment, entity_id: @capital_commitment.entity_id,
                                    signatory_ids: @capital_commitment.signatory_ids,
                                    reason: "Signature required on SPA : #{@capital_commitment.entity.name}").next_step
        end
      else
        Rails.logger.debug { "Skipping as CapitalCommitment #{@capital_commitment.id} does not have #{agreement_file_name}" }
      end
    end
  end

  def cleanup_prev
    # Check if we already ahve a document with spa_file_name
    doc = Document.where(entity_id: @capital_commitment.entity_id, owner: @capital_commitment, name: signed_file_name).first
    if doc.present?
      # If we force the regeneration, then delete the old document with spa_file_name
      AdhaarEsign.where(document_id: doc.id).each(&:destroy)
      doc.destroy

      # Remove the Signature Workflow associated with this capital_commitment
      SignatureWorkflow.where(owner: @capital_commitment, entity_id: @capital_commitment.entity_id).each(&:destroy)
    end
  end

  def signature_completed(signature_type, file)
    Rails.logger.debug { "CapitalCommitment #{@capital_commitment.id} signature_completed #{signature_type}" }
    if signature_type == "adhaar"
      doc = Document.where(entity_id: @capital_commitment.entity_id, owner: @capital_commitment, name: signed_file_name).first
      doc.locked = true
      doc.orignal = true
      doc.file = File.open(file, "rb")
      doc.save

      @capital_commitment.esign_completed = true
      @capital_commitment.save
    end
  end
end
