# frozen_string_literal: true

# Represents a single message in an AgentChatSession.
# Role is either "user" or "assistant".
#
# @see AgentChatSession

class AgentChatMessage < ApplicationRecord
  belongs_to :agent_chat_session
  has_one :feedback, class_name: "AgentChatMessageFeedback", dependent: :destroy

  CHANNELS = %w[web whatsapp].freeze

  validates :channel, presence: true, inclusion: { in: CHANNELS }

  scope :assistant_messages, -> { where(role: "assistant") }
  scope :guide_misses, -> { where(role: "assistant", guide_search_hit: false) }

  # @return [Boolean]
  def assistant?
    role == "assistant"
  end

  attribute :metadata, default: {}

  validates :role, length: { maximum: 20 }, allow_blank: true
end
