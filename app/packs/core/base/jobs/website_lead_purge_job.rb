# Enforces the WebsiteLead retention windows published in the website's privacy
# policy: visitor IP and user-agent are nulled after 90 days, whole leads deleted
# after 24 months. Idempotent, so a missed run costs nothing but a day.
#
# Was a `whenever`/cron rake task (website_leads:purge); moved into
# sidekiq-cron so a daily run doesn't fork a whole new Rails boot just for
# this. See config/initializers/sidekiq.rb for the schedule.
#
# @see WebsiteLeadRetention
# @see docs/modules/website/website_lead_capture.md
class WebsiteLeadPurgeJob < ApplicationJob
  queue_as :low

  def perform
    as_of = Time.current

    # 1. Abuse-control data first, and separately from deletion. request_ip and
    #    user_agent are collected for one narrow purpose and outlive it long
    #    before the lead itself does — nulling them keeps the business contact
    #    (which the prospect asked us to have) while dropping the personal data
    #    they never volunteered.
    #
    #    in_batches, not update_all on the whole scope: this table is small today
    #    but the endpoint is public, so a spam flood is the one growth path it
    #    has. Batching keeps a bad day from locking a big range of rows at once.
    stripped = 0
    WebsiteLead.abuse_data_expired(as_of).in_batches(of: 1_000) do |batch|
      stripped += batch.update_all(request_ip: nil, user_agent: nil)
    end

    # 2. Then whole records past the full window.
    #
    #    delete_all, not destroy_all: WebsiteLead has no callbacks and no
    #    dependent associations, so instantiating every row to destroy it would
    #    be pure waste.
    deleted = 0
    WebsiteLead.expired(as_of).in_batches(of: 1_000) do |batch|
      deleted += batch.delete_all
    end

    message = "WebsiteLeadPurgeJob — stripped abuse data from #{stripped} lead(s) older than " \
              "#{WebsiteLeadRetention::ABUSE_DATA_WINDOW.inspect}, deleted #{deleted} lead(s) older than " \
              "#{WebsiteLeadRetention::LEAD_WINDOW.inspect}"
    Rails.logger.info message
  end
end
