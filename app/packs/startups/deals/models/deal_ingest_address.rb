# frozen_string_literal: true

# One-per-deal email address for the Deal Update Agent.
#
# The address identifies the deal; the sender's From email identifies the
# user. Default address is the deal ID (e.g. "42@dev.caphive.app"), but
# users can set a custom local-part (e.g. "fund-ii-2026@dev.caphive.app").
# Global uniqueness is enforced at both model and DB level.
#
# @see DealIngestProcessor for the inbound processing pipeline
# @see ProcessDealIngestJob for the async processing job
class DealIngestAddress < ApplicationRecord
  belongs_to :deal

  # --- Scopes ---

  scope :for_lookup, ->(addr) { where(address: addr) }

  # --- Validations ---

  validates :address, presence: true,
                      uniqueness: { case_sensitive: false, message: "is already in use — try another" },
                      length: { maximum: 100 },
                      format: { with: /\A[a-z0-9][a-z0-9._-]*\z/,
                                message: "must start with a letter or number and contain only lowercase letters, numbers, dots, hyphens, or underscores" }
  validates :deal_id, uniqueness: { message: "already has an ingest address" }

  # --- Callbacks ---

  before_validation :generate_address, on: :create

  # --- Instance Methods ---

  # Full email address including the domain.
  #
  # @return [String] e.g. "42@dev.caphive.app"
  def full_address
    "#{address}@#{self.class.domain}"
  end

  # --- Class Methods ---

  # The email domain for ingest addresses.
  # Returns nil when not configured — callers use this to gate the
  # feature: no domain = address UI hidden, no addresses generated.
  #
  # @return [String, nil] e.g. "dev.caphive.app", or nil if not configured
  def self.domain
    ENV.fetch("DEAL_INGEST_DOMAIN", nil)
  end

  private

  # Default address is the deal's ID — shortest, always unique, readable.
  # Only sets on create when no custom address was provided.
  def generate_address
    self.address = deal&.id&.to_s if address.blank?
  end
end
