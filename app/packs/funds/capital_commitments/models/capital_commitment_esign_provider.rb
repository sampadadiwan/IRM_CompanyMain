# TODO: - this is not completed.
class CapitalCommitmentEsignProvider
  def initialize(capital_commitment)
    @capital_commitment = capital_commitment
  end

  def spa_file_name
    "SPA for #{@capital_commitment.investor.investor_name} : CapitalCommitment #{@capital_commitment.id}"
  end

  def generate_spa_signatures
    user_ids = []
    user_ids << @capital_commitment.user.id if @capital_commitment.investor_signature_types.include?("adhaar")
    user_ids << @capital_commitment.interest.user.id if @capital_commitment.interest.buyer_signature_types.include?("adhaar") && @capital_commitment.interest

    if user_ids.present?
      doc = Document.where(entity_id: @capital_commitment.entity_id, owner: @capital_commitment, name: spa_file_name).first
      if doc.blank?
        @capital_commitment.spa.download do |tempfile|
          doc = @capital_commitment.documents.create!(name: spa_file_name, entity_id: @capital_commitment.entity_id, download: true, file: tempfile, user_id: @capital_commitment.user_id)
        end
        ae = AdhaarEsign.new.init(doc.id, user_ids.join(","), @capital_commitment, "Acceptance of SPA")
        ae.sign
        @capital_commitment.esign_required = true
        @capital_commitment.esign_link = ae.esign_link
        @capital_commitment.save
      else
        Rails.logger.debug { "CapitalCommitment #{@capital_commitment.id} already generated SPA AdhaarEsign" }
      end
    end
  end

  def signature_completed(signature_type, file)
    Rails.logger.debug { "CapitalCommitment #{@capital_commitment.id} signature_completed #{signature_type}" }
    if signature_type == "adhaar"
      doc = Document.where(entity_id: @capital_commitment.entity_id, owner: @capital_commitment, name: spa_file_name).first
      doc.locked = true
      doc.orignal = true
      doc.file = File.open(file, "rb")
      doc.save
      @capital_commitment.final_agreement = true
      @capital_commitment.esign_completed = true
      @capital_commitment.save
    end
  end
end
