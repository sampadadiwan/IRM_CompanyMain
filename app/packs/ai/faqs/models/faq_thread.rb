class FaqThread < ApplicationRecord
  belongs_to :user

  # Validations ensures we don't have broken records
  # Note: openai_thread_id might be nil initially if we create the record before calling OpenAI

  # Ensure messages is always an array
  attribute :messages, :json, default: []
end
