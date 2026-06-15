# frozen_string_literal: true

# Represents a chat session between an analyst and a SupportAgent,
# scoped to a polymorphic chattable target (e.g. a Fund or the agent itself).
# Each session belongs to one analyst and holds many AgentChatMessages.
#
# @see AgentChatMessage
# @see GenericChatAgent

class AgentChatSession < ApplicationRecord
  belongs_to :support_agent
  belongs_to :analyst, class_name: 'User'
  belongs_to :chattable, polymorphic: true, optional: true

  has_many :agent_chat_messages, dependent: :destroy
  has_many :customer_support_escalations, dependent: :destroy

  STATUSES = %w[active escalated resolved].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }
  scope :escalated, -> { where(status: "escalated") }

  # @return [Boolean]
  def escalated?
    status == "escalated"
  end

  # @return [Boolean]
  def resolved?
    status == "resolved"
  end

  # @return [Boolean]
  def active?
    status == "active"
  end
end
