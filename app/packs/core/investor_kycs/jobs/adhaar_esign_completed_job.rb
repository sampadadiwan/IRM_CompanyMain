class AdhaarEsignCompletedJob < ApplicationJob
  queue_as :default

  def perform(adhaar_esign_id, user_id = nil)
    Chewy.strategy(:atomic) do
      AdhaarEsignCompletedService.call(adhaar_esign_id, user_id)
    end
  end
end
