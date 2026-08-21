# frozen_string_literal: true

# Audit record for every authenticated email received by the Deal Update Agent.
#
# Created when an inbound email passes address lookup, sender verification,
# and SPF/DKIM/DMARC checks. Tracks the full lifecycle from receipt through
# LLM parsing to final disposition (filed as note/task, or warehoused).
#
# Emails that fail authentication are dropped silently (FR-4) and never
# recorded here — only verified emails get a row.
#
# @see DealIngestAddress for the address lookup step
# @see DealIngestProcessor for the orchestrator that updates this record
class AgentIngestedEmail < ApplicationRecord
  belongs_to :deal
  belongs_to :sender_user, class_name: "User"

  has_one :warehouse_item, dependent: :destroy
  has_one :note, foreign_key: :source_email_id
  has_one :task, foreign_key: :source_email_id

  # --- Statuses ---

  STATUSES = %w[pending filed warehoused dropped].freeze

  # --- Validations ---

  validates :message_id, presence: true, uniqueness: true
  validates :received_at, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  # --- Scopes ---

  scope :pending, -> { where(status: "pending") }
  scope :filed, -> { where(status: "filed") }
  scope :warehoused, -> { where(status: "warehoused") }

  # --- Instance Methods ---

  # Mark as successfully filed (note or task was created).
  #
  # @param confidence [BigDecimal] match confidence score (0.00–1.00)
  # @param match_tier [String] which tier matched (e.g. "A")
  # @return [Boolean] save result
  def mark_filed!(confidence:, match_tier:)
    update!(status: "filed", confidence: confidence, match_tier: match_tier)
  end

  # Mark as warehoused (couldn't auto-file, needs manual review).
  #
  # @return [Boolean] save result
  def mark_warehoused!
    update!(status: "warehoused")
  end

  # Mark as dropped (parse failure or other unrecoverable error).
  #
  # @return [Boolean] save result
  def mark_dropped!
    update!(status: "dropped")
  end

  # Store the LLM parse result on this record.
  #
  # @param result [Hash] structured parse output from DealEmailParser
  # @return [Boolean] save result
  def store_parse_result!(result)
    update!(parse_json: result)
  end
end
