# frozen_string_literal: true

# MultiSiteUserSyncOrchestrator
# -----------------------------------------------------------------------------
# Decides WHERE to sync a user and enqueues the right jobs:
# - UPSERT to every non-primary region currently granted to the user
# - DISABLE on regions that were removed (if previous_regions is provided)
#
# Triggers:
# - If force_all: true  → always UPSERT to all non-primary regions
# - Else if user.needs_sync? → UPSERT to all non-primary regions
# - Regardless, if previous_regions is provided, DISABLE removed regions
#
# Notes:
# - This service does not “mark synced.” Leave that to your delivery policy
#   (e.g., after all targets succeed, or via reconciliation).
class MultiSiteUserSyncOrchestrator
  Result = Struct.new(
    :enqueued_upserts,     # Array<String> regions
    :enqueued_disables,    # Array<String> regions
    :skipped_reason,       # String or nil
    keyword_init: true
  )

  # @param user [User]
  # @param force_all [Boolean] seed all non-primary regions regardless of CCF
  # @param previous_regions [Array<String>, nil] pass prior value to compute removed regions
  # @param event_id [String, nil] optional idempotency key propagated to jobs
  # @return [Result]
  def self.call(user:, force_all: false, previous_regions: nil, event_id: nil)
    new(user, force_all, previous_regions, event_id).call
  end

  def initialize(user, force_all, previous_regions, event_id)
    @user             = user
    @force_all        = force_all
    @event_id         = event_id
    @primary          = norm(user.primary_region)
    @current_regions  = norm_list(user.regions&.split(","))
    @previous_regions = norm_list(previous_regions&.split(","))
  end

  def call
    return Result.new(skipped_reason: "no_primary_region") if @primary.nil?

    targets_now = non_primary(@current_regions)
    res = Result.new(enqueued_upserts: [], enqueued_disables: [], skipped_reason: nil)
    # Decide UPSERT fanout
    if @force_all || @user.needs_sync?
      targets_now.each do |region|
        MultiSiteUserSyncJob.perform_later(@user.id, region, force: @force_all, event_id: @event_id)
        res.enqueued_upserts << region
      end
    else
      res.skipped_reason = "no_change_or_no_targets"
    end

    # Decide DISABLE for removed regions (if previous known)
    unless @previous_regions.empty?
      removed = non_primary(@previous_regions) - targets_now
      removed.each do |region|
        MultiSiteUserSyncDisableJob.perform_later(@user.id, region, reason: "removed_from_regions", event_id: @event_id)
        res.enqueued_disables << region
      end
    end

    res
  end

  private

  def norm(val)
    s = val.to_s.strip.upcase
    s.empty? ? nil : s
  end

  def norm_list(arr)
    Array(arr).filter_map { |r| norm(r) }.uniq.sort
  end

  def non_primary(regions)
    regions.reject { |r| r == @primary }
  end
end
