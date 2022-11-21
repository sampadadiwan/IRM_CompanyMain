module OfferEsign
  extend ActiveSupport::Concern

  def spa_file_name
    "SPA for #{user.full_name} : Offer #{id}"
  end

  def generate_spa_signatures_delayed
    OfferSpaSignatureJob.perform_later(secondary_sale_id, id)
  end

  def generate_spa_signatures
    user_ids = []
    user_ids << user.id if secondary_sale.seller_signature_types.set?(:adhaar)
    user_ids << interest.user.id if secondary_sale.buyer_signature_types.set?(:adhaar) && interest

    if user_ids.present?
      doc = Document.where(entity_id:, owner: self, name: spa_file_name).first
      if doc.blank?
        spa.download do |tempfile|
          doc = documents.create!(name: spa_file_name, entity_id:, download: true, file: tempfile, user_id:)
        end

        AdhaarEsign.new.init(doc.id, user_ids.join(","), self, "Acceptance of SPA").sign
      else
        Rails.logger.debug { "Offer #{id} already generated SPA AdhaarEsign" }
      end
    end
  end

  def signature_completed(signature_type, file)
    Rails.logger.debug { "Offer #{id} signature_completed #{signature_type}" }
    if signature_type == "adhaar"
      doc = Document.where(entity_id:, owner: self, name: spa_file_name).first
      doc.locked = true
      doc.orignal = true
      doc.file = File.open(file, "rb")
      doc.save
      self.final_agreement = true
      save
    end
  end
end
