class AdhaarEsign < ApplicationRecord
  belongs_to :entity
  belongs_to :document
  belongs_to :user

  def init(document_id, user_id)
    self.document = Document.find(document_id)
    self.entity_id = document.entity_id
    self.user_id = user_id
  end

  def create_esign_link
    document.file.download do |tmp_file|
      response = AdhaarEsignHelper.new.sign(user.full_name, user.email, user.phone, tmp_file.path)
      if response.success?
        self.esign_document_reponse = response.body
        self.esign_url = response["result"]["source_output"]["esign_details"][0]["esign_url"]
        self.esign_doc_id = response["result"]["source_output"]["esign_doc_id"]
      else
        self.esign_document_reponse = response.message
      end
      save
    end
  end

  def retrieve_signed
    response = AdhaarEsignHelper.new.retrieve_signed(esign_doc_id)
    if response.success?
      save_esign_file(response, esign_doc_id)
    else
      Rails.logger.debug { "retrieve_signed #{esign_doc_id}, Response code = #{response.code}, Response message = #{response.message}" }
    end
    response
  end

  def save_esign_file(response, esign_doc_id)
    body = JSON.parse response.body
    self.esign_retrieve_reponse = body
    esign_file = body["result"]["source_output"]["file_details"]["esign_file"][0]

    doc_response = HTTParty.get(esign_file)
    if doc_response.success?
      self.is_signed = body["result"]["source_output"]["request_details"][0]["is_signed"]
      if is_signed
        self.signed_file_url = esign_file
        raw_file_data = Base64.decode64(doc_response.body)
        File.binwrite("tmp/#{esign_doc_id}.pdf", raw_file_data)
        Rails.logger.debug { "Wrote signed file to tmp/#{esign_doc_id}.pdf" }
      else
        Rails.logger.debug { "Not signed #{esign_doc_id}" }
      end
    else
      Rails.logger.debug { "Document Response code = #{doc_response.code}, Response message = #{doc_response.message}" }
    end

    save
  end
end
