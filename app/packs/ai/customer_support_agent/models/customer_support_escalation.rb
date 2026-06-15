# frozen_string_literal: true

# @see AgentChatSession
# Tracks handoffs from the Customer Support Agent to the human CS team.
# Created when the agent calls EscalateToHumanTool or hits the ReAct iteration cap.
class CustomerSupportEscalation < ApplicationRecord
  REASONS = %w[customer_requested low_confidence complex_issue max_iterations].freeze
  STATUSES = %w[open resolved dismissed].freeze

  belongs_to :agent_chat_session
  belongs_to :user
  belongs_to :entity
  belongs_to :resolved_by, class_name: "User", optional: true

  validates :reason, presence: true, inclusion: { in: REASONS }
  validates :status, presence: true, inclusion: { in: STATUSES }

  scope :open_items, -> { where(status: "open") }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }

  # @param user [User] the CS team member resolving the escalation
  # @param notes [String] optional resolution notes
  # @return [Boolean]
  def resolve!(user, notes: nil)
    update!(
      status: "resolved",
      resolved_by: user,
      resolved_at: Time.current
    )
    agent_chat_session.update!(status: "active")
  end

  # @return [Boolean]
  def open?
    status == "open"
  end
end
