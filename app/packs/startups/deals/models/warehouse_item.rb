# frozen_string_literal: true

# Parking lot for emails the Deal Update Agent couldn't auto-file.
#
# Created when the LLM returns an unknown intent or when stakeholder
# matching doesn't produce a high-confidence result. Sits in the
# warehouse until a team member manually files it (picks the right
# stakeholder and creates the note/task) or discards it.
#
# The warehouse is the safety net — "if uncertain, warehouse, never guess."
#
# @see AgentIngestedEmail for the source email record
# @see WarehouseItemsController for the manual filing UI
class WarehouseItem < ApplicationRecord
  belongs_to :agent_ingested_email
  belongs_to :deal
  belongs_to :resolved_by, class_name: "User", optional: true

  # --- Resolutions ---

  RESOLUTIONS = %w[filed discarded].freeze

  # --- Validations ---

  validates :resolution, inclusion: { in: RESOLUTIONS }, allow_nil: true

  # --- Scopes ---

  scope :pending, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }
  scope :for_deal, ->(deal) { where(deal: deal).pending }

  # --- Instance Methods ---

  # Whether this item is still awaiting manual review.
  #
  # @return [Boolean]
  def pending?
    resolved_at.nil?
  end

  # Resolve this item — either filed (note/task created) or discarded.
  #
  # @param user [User] the user who resolved it
  # @param resolution [String] "filed" or "discarded"
  # @return [Boolean] save result
  def resolve!(user:, resolution:)
    update!(
      resolved_at: Time.current,
      resolved_by: user,
      resolution: resolution
    )
  end
end
