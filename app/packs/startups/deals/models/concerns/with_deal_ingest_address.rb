# frozen_string_literal: true

# Generates a DealIngestAddress when a deal is created.
#
# Included in Deal. Creates one address per deal using the deal's ID
# as the default local-part. Skipped when DEAL_INGEST_DOMAIN is not
# configured (feature is disabled on that environment).
#
# No revocation — the address lives as long as the deal. Auth is
# checked at send time (sender must have deal access).
#
# @see DealIngestAddress for the address model
# @see DealIngestAuthenticator for the send-time auth check
module WithDealIngestAddress
  extend ActiveSupport::Concern

  included do
    has_one :deal_ingest_address, dependent: :destroy
    after_commit :generate_deal_ingest_address, on: :create
  end

  # Lazy-generate the address if it doesn't exist yet.
  # Called from DealsController#show for existing deals that
  # predate the feature. Uses the writing connection because
  # show requests read from the replica by default.
  #
  # @return [DealIngestAddress, nil] nil when feature is disabled
  def ensure_deal_ingest_address
    return nil if DealIngestAddress.domain.blank?

    deal_ingest_address || ActiveRecord::Base.connected_to(role: :writing) do
      create_deal_ingest_address
    end
  rescue ActiveRecord::RecordNotUnique
    reload_deal_ingest_address
  end

  private

  # Generate address on deal creation. Skipped when the feature
  # is disabled (no DEAL_INGEST_DOMAIN configured).
  def generate_deal_ingest_address
    return if DealIngestAddress.domain.blank?

    create_deal_ingest_address unless deal_ingest_address
  rescue ActiveRecord::RecordNotUnique
    # Another thread/process beat us — safe to ignore
  end
end
