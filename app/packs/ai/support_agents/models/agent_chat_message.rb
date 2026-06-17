# frozen_string_literal: true

# Represents a single message in an AgentChatSession.
# Role is either "user" or "assistant".
#
# @see AgentChatSession

class AgentChatMessage < ApplicationRecord
  belongs_to :agent_chat_session

  attribute :metadata, default: {}

  validates :role, length: { maximum: 20 }, allow_blank: true
end
