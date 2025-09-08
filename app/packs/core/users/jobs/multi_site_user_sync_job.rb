# frozen_string_literal: true

# Queued per (user, target_region). Sends a snapshot UPSERT to the target region.
# - Skips if target_region == primary_region
# - Skips if target_region not in user's regions (unless force: true)
# - Skips if no canonical change AND not forced (to avoid useless traffic)
#
# Transport (HTTP/mTLS/HMAC) is delegated to SyncApiClient (to be implemented next).
class MultiSiteUserSyncJob < ApplicationJob
  queue_as :sync

  # @param user_id [Integer]
  # @param target_region [String] e.g., "US", "IN", "SG" (case-insensitive)
  # @param force [Boolean] set true when region was newly added (initial seed)
  # @param event_id [String,nil] optional idempotency key; defaults to UUID
  def perform(user_id, target_region, force: false, event_id: nil)
    user = User.find_by(id: user_id)
    return unless user

    target = normalize_region(target_region)
    primary = normalize_region(user.primary_region)
    regions = normalize_regions(user.regions)

    # Skip primary
    if target == primary
      Rails.logger.info("[MultiSiteUserSyncJob] Skip: target is primary (user=#{user.email}, region=#{target})")
      return
    end

    # Ensure target is intended, unless forced
    unless force || regions.include?(target)
      Rails.logger.warn("[MultiSiteUserSyncJob] Skip: region not permitted (user=#{user.email}, region=#{target})")
      return
    end

    # Only send if there’s something to do, unless forced
    if !force && user.last_synced_ccf_hex.present? && user.ccf_hex == user.last_synced_ccf_hex
      Rails.logger.info("[MultiSiteUserSyncJob] No change (user=#{user.email}, region=#{target}, ccf=#{user.last_synced_ccf_hex})")
      return
    end

    envelope = UserSyncEnvelopeBuilder.build(
      user: user,
      target_region: target,
      event_id: event_id
    )

    # Transport is a separate piece; define its API and error classes up front.
    # Expectation: post_user_upsert! raises RetryableError on 5xx/timeouts,
    # raises FatalError on 4xx conflicts/validation issues.
    SyncApiClient.post_user_upsert!(target_region: target, envelope: envelope)
    user.update!(last_synced_ccf_hex: user.ccf_hex, last_synced_at: Time.current)

    Rails.logger.info("[MultiSiteUserSyncJob] Enqueued UPSERT to #{target} for #{user.email} (event_id=#{envelope[:event_id]}, ccf=#{envelope[:ccf_hex]})")
  rescue SyncApiClient::RetryableError => e
    Rails.logger.warn("[MultiSiteUserSyncJob] Retryable transport error: #{e.class} #{e.message}")
    raise # let ActiveJob retry with backoff
  rescue SyncApiClient::FatalError => e
    Rails.logger.error("[MultiSiteUserSyncJob] Fatal transport error (re-raising): #{e.class} #{e.message}")
    raise # re-raise FatalError to be caught by orchestrator
  end

  private

  def normalize_region(region_value)
    region_value.to_s.strip.upcase.presence
  end

  def normalize_regions(regions_input)
    regions_array = begin
      # Attempt to parse as JSON array first
      parsed = JSON.parse(regions_input.to_s)
      parsed.is_a?(Array) ? parsed : regions_input.to_s.split(",")
    rescue JSON::ParserError
      # If not a valid JSON, treat as a comma-separated string
      regions_input.to_s.split(",")
    end

    regions_array.filter_map { |s| normalize_region(s) }.uniq.sort
  end
end
