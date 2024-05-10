class DocumentPostCreateJob < ApplicationJob
  queue_as :low

  def perform(document_id)
    Chewy.strategy(:sidekiq) do
      document = Document.find(document_id)
      document.post_create_actions
    end
  end
end
