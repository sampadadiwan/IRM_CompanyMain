# Tells us a demo request came in from the public website.
#
# This is the alert that GTM prerequisite A2 measures ("a submission produces an
# alert within 5 minutes"), so it goes to a monitored shared mailbox rather
# than through the entity -> user notification machinery, which needs a tenant
# this record does not have.
#
# @see WebsiteLeadCreate
# @see docs/modules/website/website_lead_capture.md
class WebsiteLeadMailer < ApplicationMailer
  # Inbound leads go to the commercial mailbox, NOT to SUPPORT_EMAIL_TO — that
  # address is the support/exception firehose (ExceptionNotifier, escalations,
  # entity alerts) and a prospect waiting on a five-minute reply must not be
  # buried in it. Kept as its own env var so a deployment can redirect leads
  # without moving every other alert with them.
  DEFAULT_RECIPIENT = "hello@caphive.com".freeze

  def new_lead
    @website_lead = WebsiteLead.find(params[:website_lead_id])

    # Subject carries the firm so the mailbox is triageable without opening
    # anything. Sanitised because it is visitor-supplied and a newline in a
    # header is header injection.
    firm = @website_lead.firm.to_s.gsub(/[[:cntrl:]]/, " ").squish
    subject = "[Website] Demo request#{" — #{firm}" if firm.present?}"

    mail(
      from: ENV.fetch("SUPPORT_EMAIL_FROM", nil),
      to: ENV["WEBSITE_LEADS_EMAIL_TO"].presence || DEFAULT_RECIPIENT,
      # Replying to the alert reaches the prospect directly, which is the whole
      # point of a five-minute response commitment. reply_to is safe to set from
      # visitor input only because the address passed WebsiteLead's format
      # validation, which rejects the whitespace and control characters that
      # would let it inject a second header.
      reply_to: @website_lead.email,
      subject: subject
    )
  end
end
