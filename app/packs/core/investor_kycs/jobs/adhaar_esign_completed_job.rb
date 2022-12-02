class AdhaarEsignCompletedJob < ApplicationJob
  queue_as :critical

  def perform(adhaar_esign_id, user_id = nil)
    Chewy.strategy(:sidekiq) do
      AdhaarEsignCompletedService.call(adhaar_esign_id:, user_id:)
    end
  end
end
