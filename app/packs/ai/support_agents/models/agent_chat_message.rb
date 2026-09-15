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
  # Assistant replies where guide search ran and found nothing, or nothing that matched
  # two-thirds of the search terms (GuideSearch::STRONG_MATCH_RATIO). Replies that never searched
  # the guides (guide_search_terms is nil) are not misses.
  scope :guide_misses, lambda {
    where(role: "assistant").where.not(guide_search_terms: nil)
                            .where("agent_chat_messages.guide_search_hit = ? OR agent_chat_messages.guide_search_strong_hit = ?", false, false)
  }

  # @return [AgentChatMessage, nil] the user message this assistant reply answered
  def preceding_user_message
    agent_chat_session.agent_chat_messages.where(role: "user").where(created_at: ..created_at).order(created_at: :desc, id: :desc).first
  end

  # @return [Boolean]
  def assistant?
    role == "assistant"
  end

  attribute :metadata, default: {}

  validates :role, length: { maximum: 20 }, allow_blank: true
end
