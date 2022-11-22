# Complex processing below
# For an Offer the following steps are taken
# 1. When SecondarySaleNotifiers.notify_spa_sellers is called, it triggers the AdharEsign process for all Offers
# 2. The OfferSpaSignatureJob calls the offer.generate_spa_signatures
# 3. This triggers the AdhaarEsign.sign method
# 4. The user link is created and sent, and once the user completes signing, he is redirected to /adhaar_esigns/#{id}/completed
# 5. That then triggers AdhaarEsignCompletedJob
# 6. That retrives the doc and calls back the offer.signature_completed, which uploads the signed doc

class AdhaarEsign < ApplicationRecord
  self.table_name = "adhaar_esigns"
  belongs_to :entity
  belongs_to :document
  belongs_to :owner, polymorphic: true, optional: true

  def init(document_id, user_ids, owner, reason)
    self.document = Document.find(document_id)
    self.entity_id = document.entity_id
    self.user_ids = user_ids
    self.owner = owner
    self.reason = reason
    @esign_helper ||= DigioEsignHelper.new
    self
  end

  def redirect_url
    base_url = ENV['NGROK_HOST'].present? ? "http://#{ENV['NGROK_HOST']}" : ENV['BASE_URL']
    base_url + "/adhaar_esigns/#{id}/completed"
  end

  def esign_link(phone = "phone_number")
    "https://ext.digio.in/#/gateway/login/#{esign_doc_id}/#{rand(4**4)}/#{phone}?redirect_url=#{redirect_url}&logo=https://app.caphive.com/img/logo_big.png"
  end

  def sign
    Rails.logger.debug { "Creating signing link for users #{user_ids} for document #{document_id}" }
    @esign_helper ||= DigioEsignHelper.new
    document.file.download do |tmp_file|
      response = @esign_helper.sign(user_ids, document.name, tmp_file.path, reason)
      if response.success?
        self.esign_document_reponse = response.body
        self.esign_doc_id = response["id"]
      else
        self.esign_document_reponse = response.message
      end
      save
    end
  end

  def download_file_name
    "tmp/#{esign_doc_id}.pdf"
  end

  def retrieve_signed
    @esign_helper ||= DigioEsignHelper.new
    response = @esign_helper.retrieve_signed(esign_doc_id)
    self.esign_retrieve_reponse = response["agreement_status"]
    if response.success?
      self.is_signed = true
      response["signing_parties"].each do |sp|
        self.is_signed &&= sp["status"] == "signed"
      end
      if self.is_signed
        Rails.logger.debug { "#{esign_doc_id} : All parties have signed, downloading file" }
        # Save the signed file to tmp
        save_esign_file(download_file_name)
        # Callback to the owner that the signed doc is now awailable
        owner.signature_completed("adhaar", download_file_name) if owner.respond_to?(:signature_completed)
      else
        Rails.logger.debug { "#{esign_doc_id} : Not all parties have signed" }
      end
    else
      Rails.logger.debug { "retrieve_signed #{esign_doc_id}, Response code = #{response.code}, Response message = #{response.message}" }
    end
    save
    response
  end

  def save_esign_file(file_name)
    @esign_helper ||= DigioEsignHelper.new
    response = @esign_helper.download(esign_doc_id)

    if response.success?
      raw_file_data = response.body
      File.binwrite(file_name, raw_file_data)
      Rails.logger.debug { "Wrote signed file to tmp/#{esign_doc_id}.pdf" }
    else
      Rails.logger.debug { "Document Response code = #{response.code}, Response message = #{response.message}" }
    end

    response
  end
end
