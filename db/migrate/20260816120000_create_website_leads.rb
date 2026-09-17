# Demo requests submitted from the public website (caphive.com / caphive.us).
#
# See docs/technical/website_lead_capture.md.
#
# Deliberately NOT tenant-scoped. Every other table in this app hangs off an
# entity_id; this one cannot, because the row is created by an anonymous visitor
# before any relationship exists. That is why WebsiteLeadPolicy gates reads on
# the :support / :super roles rather than on tenancy — there is no tenant to
# scope to, so role is the only available boundary.
#
# The columns split into three groups with three different lifetimes:
#
#   the lead      name/email/firm/role/message — ordinary business-contact data
#   attribution   utm_*/landing_page/referrer — how they found us
#   abuse control request_ip/user_agent — personal data kept only to spot floods
#
# The third group is purged on a much shorter clock than the first two. See
# lib/tasks/website_leads.rake and the privacy policy's retention section.
class CreateWebsiteLeads < ActiveRecord::Migration[8.1]
  def change
    create_table :website_leads do |t|
      # ---- the lead itself ----
      t.string :name, null: false
      t.string :email, null: false
      t.string :firm
      # Free text from a <select>, not an enum: the option list on the website is
      # marketing copy and changes without a deploy of this app.
      t.string :role

      # The highest-value field — the prospect's problem in their own words.
      # Text, not string: MySQL would silently truncate at 255 and this is the one
      # field we never want clipped.
      t.text :message

      # ---- attribution ----
      t.string :utm_source
      t.string :utm_medium
      t.string :utm_campaign
      t.string :utm_content
      t.string :utm_term

      # Which page the form was submitted from, e.g. "contact.html". Sent by the
      # client as _source_page.
      t.string :landing_page
      # Read from the Referer header — the client does not send one.
      t.string :referrer

      # ---- provenance ----
      # Server clock. Never client-supplied: a lead that can backdate itself
      # corrupts every channel report built on top of this table.
      t.datetime :submitted_at, null: false

      # Nullable because the purge task nulls them once the abuse-control window
      # closes, while keeping the lead itself.
      # 45 chars covers an IPv6 address with an IPv4-mapped suffix.
      t.string :request_ip, limit: 45
      t.string :user_agent, limit: 512

      # Everything received, as JSON, minus the fields we deliberately drop
      # (honeypot, timing stamp). Form field names on the website drift without a
      # deploy here; an unparsed field beats a lost one.
      t.text :raw_payload

      t.timestamps
    end

    # The admin index, which is always "newest first".
    add_index :website_leads, :submitted_at

    # "Have we heard from this firm before?" — the question asked before replying.
    add_index :website_leads, :email

    # The channel report behind the GTM kill criteria: leads per source per month.
    add_index :website_leads, %i[utm_source submitted_at]

    # The purge task's scan: rows still holding abuse-control data past the window.
    add_index :website_leads, %i[request_ip submitted_at]
  end
end
