# frozen_string_literal: true

# Sends a DISABLE command to a target region for a given user.
# This removes access in that region (soft-disable), preserving audit trails.
class MultiSiteUserSyncDisableJob < ApplicationJob
  queue_as :sync

  # @param user_id [Integer]
  # @param target_region [String] e.g., "IN"
  # @param reason [String] "removed_from_regions" | "user_disabled"
  # @param event_id [String, nil]
  def perform(user_id, target_region, reason: "removed_from_regions", event_id: nil)
    user = User.find_by(id: user_id)
    return unless user

    target  = target_region.to_s.strip.upcase
    primary = user.primary_region.to_s.strip.upcase

    if target.blank? || target == primary
      Rails.logger.info("[MultiSiteUserSyncDisableJob] Skip (target is blank or primary) user=#{user.email} region=#{target}")
      return
    end

    SyncApiClient.post_user_disable!(
      target_region: target,
      email: user.email,
      origin_region: primary,
      reason: reason,
      event_id: event_id.presence || SecureRandom.uuid
    )

    Rails.logger.info("[MultiSiteUserSyncDisableJob] Disabled in #{target} for #{user.email} (reason=#{reason})")
  rescue SyncApiClient::RetryableError => e
    Rails.logger.warn("[MultiSiteUserSyncDisableJob] Retryable transport error: #{e.class} #{e.message}")
    raise
  rescue SyncApiClient::FatalError => e
    Rails.logger.error("[MultiSiteUserSyncDisableJob] Fatal transport error (dropping): #{e.class} #{e.message}")
  end
end
