# frozen_string_literal: true

# @see AgentChatMessage
# Stores user ratings (thumbs up/down) and LLM judge scores for agent responses.
# One row per assistant message — user feedback and judge scores upsert into the same record.
class AgentChatMessageFeedback < ApplicationRecord
  RATINGS = %w[positive negative].freeze
  STATUSES = %w[open needs_review resolved dismissed pending_engineering].freeze

  belongs_to :agent_chat_message
  belongs_to :user, optional: true
  belongs_to :entity
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :rating, inclusion: { in: RATINGS }, allow_nil: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :judge_completeness, numericality: { in: 0..3 }, allow_nil: true
  validates :judge_grounding, numericality: { in: 0..3 }, allow_nil: true
  validates :judge_actionability, numericality: { in: 0..3 }, allow_nil: true
  validates :judge_total, numericality: { in: 0..9 }, allow_nil: true

  scope :needs_review, -> { where(status: "needs_review") }
  scope :open_items, -> { where(status: %w[open needs_review]) }
  scope :for_entity, ->(entity_id) { where(entity_id: entity_id) }
  scope :negative, -> { where(rating: "negative") }
  scope :flagged, -> { where(status: "needs_review").or(where(rating: "negative")) }

  # @return [Boolean] true if judge has scored this message
  def judged?
    judge_total.present?
  end

  # @return [Boolean] true if user has rated this message
  def rated?
    rating.present?
  end
end
