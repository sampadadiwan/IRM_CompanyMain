class AdhaarEsignDigio < ApplicationRecord
  self.table_name = "adhaar_esigns"
  belongs_to :entity
  belongs_to :document

  def init(document_id, user_ids)
    self.document = Document.find(document_id)
    self.entity_id = document.entity_id
    self.user_ids = user_ids

    @esign_helper ||= DigioEsignHelper.new
    self
  end

  def sign_link
    "https://ext.digio.in/#/gateway/login/#{esign_doc_id}"
  end

  def sign
    @esign_helper ||= DigioEsignHelper.new
    document.file.download do |tmp_file|
      response = @esign_helper.sign(user_ids, document.name, tmp_file.path)
      if response.success?
        self.esign_document_reponse = response.body
        self.esign_doc_id = response["id"]
      else
        self.esign_document_reponse = response.message
      end
      save
    end
  end

  def retrieve_signed
    @esign_helper ||= DigioEsignHelper.new
    response = @esign_helper.retrieve_signed(esign_doc_id)
    self.esign_retrieve_reponse = response["agreement_status"]
    if response.success?
      all_signed = true
      response["signing_parties"].each do |sp|
        all_signed &&= sp["status"] == "signed"
      end
      if all_signed
        Rails.logger.debug { "#{esign_doc_id} : All parties have signed, downloading file" }
        save_esign_file
      else
        Rails.logger.debug { "#{esign_doc_id} : Not all parties have signed" }
      end
    else
      Rails.logger.debug { "retrieve_signed #{esign_doc_id}, Response code = #{response.code}, Response message = #{response.message}" }
    end
    save
    response
  end

  def save_esign_file
    @esign_helper ||= DigioEsignHelper.new
    response = @esign_helper.download(esign_doc_id)

    if response.success?
      raw_file_data = response.body
      File.binwrite("tmp/#{esign_doc_id}.pdf", raw_file_data)
      Rails.logger.debug { "Wrote signed file to tmp/#{esign_doc_id}.pdf" }
    else
      Rails.logger.debug { "Document Response code = #{response.code}, Response message = #{response.message}" }
    end

    response
  end
end
