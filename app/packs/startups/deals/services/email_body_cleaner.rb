# frozen_string_literal: true

# Strips email signatures and quoted reply chains from inbound email bodies.
#
# Uses the email_reply_parser gem (by GitHub) as the core engine for
# detecting and removing quoted text and signatures. Wraps it in a
# service interface consistent with the deal ingest pipeline.
#
# Called by DealIngestProcessor before passing the body to the LLM parser,
# so the AI sees only the sender's new content — no wasted tokens on
# quoted replies or "Sent from my iPhone" signatures.
#
# @example
#   EmailBodyCleaner.call("Great call today\n\n-- \nJohn Doe\nVP, Acme Corp")
#   # => "Great call today"
#
# @see DealIngestProcessor#parse_email where this is called
# @see https://github.com/github/email_reply_parser
class EmailBodyCleaner
  # Strip signatures and quoted replies from an email body.
  #
  # @param body [String] raw email body text
  # @return [String] cleaned body with only the sender's new content
  def self.call(body)
    return "" if body.blank?

    EmailReplyParser.parse_reply(body).strip
  end
end
