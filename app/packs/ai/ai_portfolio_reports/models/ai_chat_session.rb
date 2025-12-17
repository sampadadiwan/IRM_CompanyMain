# app/models/ai_chat_session.rb
class AiChatSession < ApplicationRecord
  belongs_to :ai_portfolio_report
  belongs_to :analyst, class_name: 'User'

  has_many :ai_chat_messages, dependent: :destroy
end
