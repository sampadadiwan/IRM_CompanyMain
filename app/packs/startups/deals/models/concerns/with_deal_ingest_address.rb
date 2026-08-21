# frozen_string_literal: true

# Automatically generates and revokes DealIngestAddress records when
# deal access rights are created or destroyed.
#
# Included in AccessRight. Hooks into the existing after_commit and
# after_destroy_commit lifecycle to keep ingest addresses in sync
# with deal access — ensuring security rule FR-5 (revoking deal access
# revokes the address).
#
# Only fires for user-level access rights on Deal owners. Category-level
# and investor-level access rights are ignored (they don't map to a
# single user who can send emails).
#
# @see DealIngestAddress for the address model
module WithDealIngestAddress
  extend ActiveSupport::Concern

  included do
    after_commit :generate_deal_ingest_address, on: %i[create]
    after_destroy_commit :revoke_deal_ingest_address
  end

  private

  # Generate a DealIngestAddress when a user is granted access to a deal.
  # If a revoked address exists (from a prior access grant), reactivate it
  # rather than creating a new one — MySQL's unconditional unique index on
  # [deal_id, user_id] prevents duplicate rows.
  def generate_deal_ingest_address
    return unless deal_access_right_for_user?

    addr = DealIngestAddress.find_or_initialize_by(deal_id: owner_id, user_id: user_id)
    if addr.persisted? && addr.revoked?
      addr.update!(revoked_at: nil)
    else
      addr.save!
    end
  end

  # Revoke the DealIngestAddress when a user's deal access is removed.
  # Sets revoked_at rather than deleting — preserves audit trail.
  def revoke_deal_ingest_address
    return unless deal_access_right_for_user?

    DealIngestAddress.active.where(deal_id: owner_id, user_id: user_id).find_each(&:revoke!)
  end

  # Only act on user-level access rights for Deal owners.
  # Category-level and investor-level rights don't map to a single user.
  #
  # @return [Boolean]
  def deal_access_right_for_user?
    owner_type == "Deal" && user_id.present?
  end
end
