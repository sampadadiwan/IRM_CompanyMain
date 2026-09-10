# frozen_string_literal: true

# Support-agent-specific email helpers.
#
# The generic building blocks (sa_banner, sa_section, sa_th/sa_td, sa_callout, sa_cta,
# sa_stat_tiles, …) moved to EmailStyleHelper in core — funds and core mailers use them
# too, and reaching into this pack for them crossed a package boundary. What is left
# here is the one piece that is genuinely about agent runs: mapping an agent's own
# status vocabulary onto a tone.
#
# Usage in a mailer:   helper SupportAgentEmailHelper
module SupportAgentEmailHelper
  include EmailStyleHelper

  # Preserved so the dozen views written against SupportAgentEmailHelper::SA_COLORS[...]
  # keep resolving. New code should reference EmailStyleHelper::SA_COLORS.
  SA_COLORS = EmailStyleHelper::SA_COLORS

  # Derive a tone from a free-form status string
  def sa_tone_for(status)
    case status.to_s
    when "pass", "success", "surplus", "ready", "complete", "on_track", "fresh" then :success
    when "fail", "failure", "shortfall", "blocked", "failed", "needs_attention"  then :danger
    when "watch", "warning", "partial", "stale"                                  then :warning
    else :muted
    end
  end
end
