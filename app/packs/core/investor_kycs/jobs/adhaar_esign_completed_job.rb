class AdhaarEsignCompletedJob < ApplicationJob
  queue_as :default

  def perform(adhaar_esign_id)
    Chewy.strategy(:sidekiq) do
      ae = AdhaarEsign.find(adhaar_esign_id)
      ae.retrieve_signed
    end
  end
end
