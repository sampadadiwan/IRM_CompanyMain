class EsignUpdateJob < ApplicationJob
  # rubocop:disable Metrics/method_length
  def perform(document_id)
    Chewy.strategy(:sidekiq) do
      # Find the document
      doc = Document.find(document_id)
      # Get api response
      response = DigioEsignHelper.new.retrieve_signed(doc.provider_doc_id)
      if response.success?
        # update document attribute
        overall_status = JSON.parse(response.body)["status"] # can be "completed" or "requested"
        doc.update(esign_status: overall_status)
        # Update each esignature's status
        response['signing_parties'].each do |signer|
          # Find user by email (identifier)
          user = User.find_by(email: signer['identifier'])
          if user
            # Find esignature for this user
            esign = doc.e_signatures.find_by(user_id: user.id)
            if esign.present?
              # Update status if changed
              if esign.status != signer['status']
                esign.add_api_update(JSON.parse(response.body))
                esign.update(status: signer['status'], api_updates: esign.api_updates)
                # UserAlert.new(user_id: user.id, message: "Document - #{doc.name}'s E-Sign status updated", level: "success").broadcast
              end
            else
              e = StandardError.new("E-Sign not found for #{doc.name} and user #{user.name} - #{JSON.parse(response.body)}")
              ExceptionNotifier.notify_exception(e)
              logger.error e.message
              # raise e
            end
          else
            e = StandardError.new("User not found for #{doc.name} with identifier #{signer['identifier']} - #{JSON.parse(response.body)}")
            ExceptionNotifier.notify_exception(e)
            logger.error e.message
            # raise e
          end
        end
        signed_esigns = doc.e_signatures.reload.where.not(status: "signed")
        signature_completed(doc) if signed_esigns.count < 1
      else
        signatures_failed(doc, response)
      end
    end
  end
  # rubocop:enable Metrics/method_length

  def signature_completed(doc)
    tmpfile = Tempfile.new("#{doc.name}.pdf", encoding: 'ascii-8bit')
    content = DigioEsignHelper.new.download(doc.provider_doc_id).body
    tmpfile.write(content)
    doc.signature_completed(tmpfile.path)
    tmpfile.close
    tmpfile.unlink
  end

  def signatures_failed(doc, response)
    e = StandardError.new("Error getting status for #{doc.name} - #{JSON.parse(response.body)}")
    ExceptionNotifier.notify_exception(e)

    doc.e_signatures.each do |esign|
      esign.add_api_update(JSON.parse(response.body))
      esign.save!
    end
    logger.error e.message
    # raise e
  end
end
