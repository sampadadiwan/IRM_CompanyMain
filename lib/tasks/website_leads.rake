# Retention enforcement for WebsiteLead.
#
# The two windows are published in the website's privacy policy, so this task is
# what makes that page true rather than aspirational. Scheduled daily from
# config/schedule.rb.
#
# @see WebsiteLeadRetention
# @see docs/technical/website_lead_capture.md
namespace :website_leads do
  desc "Strip expired abuse-control data and delete leads past the retention window"
  task purge: :environment do
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

    message = "website_leads:purge — stripped abuse data from #{stripped} lead(s) older than " \
              "#{WebsiteLeadRetention::ABUSE_DATA_WINDOW.inspect}, deleted #{deleted} lead(s) older than " \
              "#{WebsiteLeadRetention::LEAD_WINDOW.inspect}"
    Rails.logger.info message
    puts message
  end
end
