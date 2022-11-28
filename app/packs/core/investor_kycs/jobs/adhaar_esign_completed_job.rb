class AdhaarEsignCompletedJob < ApplicationJob
  queue_as :default

  def perform(adhaar_esign_id, user_id = nil)
    Chewy.strategy(:sidekiq) do
      # Ensure we retrive the signed doc from Digio and upload it to our system
      ae = AdhaarEsign.find(adhaar_esign_id)
      ae.retrieve_signed

      if user_id
        swf = SignatureWorkflow.where(entity_id: ae.entity_id, owner: ae.owner).last
        swf.mark_completed(user_id)
      end
    end
  end
end
