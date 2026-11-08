# frozen_string_literal: true

# dr:verify's "Background job ran" check: proves Sidekiq RUNS jobs from the queue real work uses,
# not just that it registered. Queued with a random token; running it writes that token to the
# cache (solid_cache, shared by every app server), which dr:verify waits for. Contacts nobody, so
# it is safe on a DR drill copy.
#
# Not SidekiqCanaryJob: the canary has its own single-thread capsule (it measures "is Sidekiq
# fetching at all") and records a Prometheus gauge that verify cannot read back.
class DrVerifyPingJob < ApplicationJob
  queue_as :default

  def self.cache_key(token)
    "dr_verify_ping:#{token}"
  end

  def perform(token)
    # A few minutes is plenty: verify polls for at most Dr::ServingChecks::JOB_TIMEOUT_SECONDS
    Rails.cache.write(self.class.cache_key(token), Time.current.to_i, expires_in: 10.minutes)
  end
end
