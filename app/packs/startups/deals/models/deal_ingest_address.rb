# frozen_string_literal: true

# Per-(deal, user) unguessable email address for the Deal Update Agent.
#
# The address is the credential — possession proves both identity and deal
# access. Generated automatically when a deal is created or a user is granted
# access. Revoked (soft-delete via revoked_at) when access is removed.
#
# @see DealIngestProcessor for the inbound processing pipeline
# @see ProcessDealIngestJob for the async processing job
class DealIngestAddress < ApplicationRecord
  belongs_to :deal
  belongs_to :user

  # --- Scopes ---

  scope :active, -> { where(revoked_at: nil) }
  scope :for_lookup, ->(addr) { active.where(address: addr) }

  # --- Validations ---

  validates :address, presence: true, uniqueness: true, length: { is: 16 }
  validates :deal_id, uniqueness: { scope: :user_id, message: "already has an address for this user" }

  # --- Callbacks ---

  before_validation :generate_address, on: :create

  # --- Instance Methods ---

  # Full email address including the domain.
  #
  # @return [String] e.g. "d7f3a91c2b8e4406@updates.caphive.com"
  def full_address
    "#{address}@#{self.class.domain}"
  end

  # Soft-revoke this address. Revoked addresses are invisible to the
  # inbound pipeline but preserved for audit trail.
  #
  # @return [Boolean] save result
  def revoke!
    update!(revoked_at: Time.current)
  end

  # Whether this address has been revoked.
  #
  # @return [Boolean]
  def revoked?
    revoked_at.present?
  end

  # --- Class Methods ---

  # The email domain for ingest addresses.
  # Returns nil when not configured — callers use this to gate the
  # feature: no domain = address UI hidden, no addresses generated.
  #
  # @return [String, nil] e.g. "updates.altconnects.com", or nil if not configured
  def self.domain
    ENV.fetch("DEAL_INGEST_DOMAIN", nil)
  end

  private

  # Generates a cryptographically random 16-hex-char address.
  # 8 bytes = 2^64 possibilities — unguessable by brute force.
  def generate_address
    self.address = SecureRandom.hex(8) if address.blank?
  end
end
