# Complex processing below
# For an Offer the following steps are taken
# 1. When SecondarySaleNotifiers.notify_spa_sellers is called, it triggers the AdharEsign process for all Offers
# 2. The OfferSpaSignatureJob calls the offer.trigger_signatures
# 3. This triggers the AdhaarEsign.sign method
# 4. The user link is created and sent, and once the user completes signing, he is redirected to /adhaar_esigns/#{id}/completed
# 5. That then triggers AdhaarEsignCompletedJob
# 6. That retrives the doc and calls back the offer.signature_completed, which uploads the signed doc

class AdhaarEsign < ApplicationRecord
  self.table_name = "adhaar_esigns"
  belongs_to :entity
  belongs_to :document
  belongs_to :owner, polymorphic: true, optional: true

  validate :ensure_owner_callback

  def initialize(params)
    super(params)
    self.entity_id ||= document.entity_id
    @esign_helper ||= DigioEsignHelper.new
  end

  # The owner must implement signature_completed
  def ensure_owner_callback
    errors.add(:owner, "needs to implement method signature_completed('adhaar', 'download_file_name')") unless owner.respond_to?(:signature_completed)
  end

  def redirect_url
    base_url = sub_domain
    base_url + "/adhaar_esigns/#{id}/completed"
  end

  # This is done cause we need to redirect back to the subdomain if it exists
  def sub_domain
    if entity.sub_domain.present?
      # Hack... Hopefully http gets redirected to https
      "http://#{entity.sub_domain.strip}.#{ENV['DOMAIN']}"
    else
      ENV['BASE_URL']
    end
  end

  def esign_link(phone)
    "https://ext.digio.in/#/gateway/login/#{esign_doc_id}/#{rand(4**4)}/#{phone}?redirect_url=#{redirect_url}&logo=https://app.caphive.com/img/logo_big.png" if esign_doc_id.present?
  end

  def user_ids
    owner.esigns.for_adhaar.pluck(:user_id)
  end

  def reason
    owner.esigns.for_adhaar.first&.reason
  end

  def sign
    success = false
    Rails.logger.debug { "Creating signing link for users #{user_ids} for document #{document_id}" }
    @esign_helper ||= DigioEsignHelper.new
    document.file.download do |tmp_file|
      response = @esign_helper.sign(user_ids, document.name, tmp_file.path, reason)
      if response.success?
        self.esign_document_reponse = response.body
        self.esign_doc_id = response["id"]
        success = true

        # Update the owner
        owner.esigns.for_adhaar.each do |esign|
          esign.link = esign_link(esign.user.phone)
          esign.save
        end

        # Setup a workflow to chase and track the signatories
        swf = SignatureWorkflow.where(owner:, entity_id: owner.entity_id).first_or_create!
        swf.next_step
      else
        self.esign_document_reponse = JSON.parse(response.body)["message"]
      end
      save
    end

    success
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
      Rails.logger.debug { "Wrote signed file to #{file_name}" }
    else
      Rails.logger.debug { "Document Response code = #{response.code}, Response message = #{response.message}" }
    end

    response
  end

  def users
    User.where(id: user_ids.split(","))
  end

  # The completion job is run as its a time consuming job to retrieve the signed doc etc
  def completed(user_id)
    AdhaarEsignCompletedJob.perform_now(id, user_id)
  end

  before_destroy :cleanup_signature_workflows
  def cleanup_signature_workflows
    # Remove the Signature Workflow associated with this capital_commitment
    SignatureWorkflow.where(owner:, entity_id: owner.entity_id).each(&:destroy)
  end
end
