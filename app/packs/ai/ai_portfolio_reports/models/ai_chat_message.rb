# app/models/ai_chat_message.rb
class AiChatMessage < ApplicationRecord
  belongs_to :ai_chat_session

  validates :role, inclusion: { in: %w[user assistant] }
  validates :content, presence: true

  store :metadata, accessors: %i[sources confidence], coder: JSON
end
