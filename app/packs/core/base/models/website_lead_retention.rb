# Retention windows for WebsiteLead, in one place.
#
# These two numbers are a published commitment, not an implementation detail:
# they appear verbatim in the website's privacy policy (website_src/pages/
# privacy.html, "How long we keep personal data"). Changing either one here
# without changing it there makes the policy false. Change both, or neither.
module WebsiteLeadRetention
  # How long request_ip and user_agent survive.
  #
  # They exist for one purpose — recognising a flood of submissions from one
  # source — and that purpose is served within days, not months. 90 days keeps
  # enough history to see a slow, patient spammer while staying short enough that
  # we are not sitting on a pile of visitor IP addresses with no use for them.
  # The lead itself is untouched by this purge.
  ABUSE_DATA_WINDOW = 90.days

  # How long the lead record itself survives after submission.
  #
  # A demo request is a business contact who asked to hear from us, and a
  # two-year sales cycle is normal in this market — a lead from 18 months ago
  # being revisited when a fund's admin contract comes up for renewal is an
  # ordinary event, not an edge case. Past 24 months the record is stale enough
  # that keeping it is hoarding rather than pipeline.
  LEAD_WINDOW = 24.months
end
