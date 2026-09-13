# Retention enforcement for WebsiteLead.
#
# The two windows are published in the website's privacy policy. The actual
# purge logic lives in WebsiteLeadPurgeJob, scheduled daily via sidekiq-cron
# (config/initializers/sidekiq.rb) — this task is just a manual/ops hook onto
# the same code path (perform_now, not perform_later: a manual invocation
# should block until done, not silently enqueue and exit).
#
# @see WebsiteLeadPurgeJob
# @see WebsiteLeadRetention
# @see docs/technical/website_lead_capture.md
namespace :website_leads do
  desc "Strip expired abuse-control data and delete leads past the retention window"
  task purge: :environment do
    WebsiteLeadPurgeJob.perform_now
  end
end
