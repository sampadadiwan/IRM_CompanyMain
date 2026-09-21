# Turns one public demo-form submission into a WebsiteLead and a notification.
#
# See docs/modules/website/website_lead_capture.md. Called from
# WebsiteLeadsController#create — the only unauthenticated write path in this
# app — so every step here runs on input from a stranger.
#
# Step order matters:
#
#   reject_bot      runs FIRST and short-circuits the whole chain. A bot must
#                   cost us nothing: no row, no email, no validation work.
#   build / save    the lead
#   handle_errors   the `left` track, so a validation failure returns field
#                   errors instead of raising
#   send_notification  last, because a lead that is stored but unannounced is
#                   recoverable, while an email about a row that failed to save
#                   is not.
#
# Bot rejection is reported to the caller as SUCCESS with ctx[:discarded] set.
# That is deliberate: the controller answers 200 either way, because telling a
# bot which check it tripped is telling it what to change next time.
class WebsiteLeadCreate < Trailblazer::Operation
  # A form filled in faster than this was not filled in by a person reading it.
  # Two seconds is forgiving — real submissions take tens of seconds — and is the
  # threshold the website's own comment cites.
  MIN_FILL_SECONDS = 2

  step :reject_bot, Output(:failure) => End(:success)
  step :build
  step :save
  left :handle_errors, Output(:failure) => End(:failure)
  step :send_notification

  # Returns FALSE for a bot, which the Output mapping above turns into an early
  # success. Two independent checks, either of which is enough:
  #
  #   _hp  honeypot. A hidden input no human ever sees, let alone fills in.
  #   _ts  the epoch-millisecond stamp written when the page rendered.
  #
  # A missing or unparseable _ts PASSES. A visitor on a page served from cache,
  # or with JS partially blocked, would otherwise be silently discarded — and a
  # silently discarded real lead is the exact failure this feature exists to end.
  def reject_bot(ctx, params:, **)
    if params[:_hp].present?
      Rails.logger.info "WebsiteLeadCreate: discarded (honeypot)"
      ctx[:discarded] = :honeypot
      return false
    end

    rendered_at_ms = params[:_ts].to_s.strip
    return true if rendered_at_ms.blank? || !rendered_at_ms.match?(/\A\d+\z/)

    elapsed = Time.current.to_f - (rendered_at_ms.to_i / 1000.0)
    # Negative elapsed means a client clock ahead of ours, not a bot. Let it pass.
    return true if elapsed.negative? || elapsed >= MIN_FILL_SECONDS

    Rails.logger.info "WebsiteLeadCreate: discarded (submitted in #{elapsed.round(2)}s)"
    ctx[:discarded] = :too_fast
    false
  end

  def build(ctx, params:, request_ip: nil, user_agent: nil, referrer: nil, **)
    ctx[:website_lead] = WebsiteLead.new(
      name: squish(params[:name]),
      email: squish(params[:email]).to_s.downcase,
      firm: squish(params[:firm]),
      role: squish(params[:role]),
      # NOT squished: line breaks are meaning in a free-text description of a
      # fund structure, and collapsing them makes the notification harder to read.
      message: params[:message].presence,
      # The client sends the page it was submitted from as _source_page.
      landing_page: truncate(params[:_source_page], WebsiteLead::URL_MAX),
      # The client sends no referrer; the header is the only source.
      referrer: truncate(referrer, WebsiteLead::URL_MAX),
      submitted_at: Time.current,
      request_ip: request_ip,
      user_agent: truncate(user_agent, WebsiteLead::USER_AGENT_MAX),
      raw_payload: raw_payload_json(params),
      **WebsiteLead::UTM_FIELDS.index_with { |field| squish(params[field]) }
    )
    true
  end

  def save(_ctx, website_lead:, **)
    website_lead.save
  end

  def handle_errors(ctx, website_lead:, **)
    ctx[:errors] = website_lead.errors.to_hash(true)
    Rails.logger.warn "WebsiteLeadCreate: rejected — #{website_lead.errors.full_messages.join(', ')}"
    # Returning false keeps the operation on the failure track, which the
    # Output mapping above routes to End(:failure).
    false
  end

  # A stored lead nobody is told about is the same as no lead, so a delivery
  # failure is logged loudly — but it does NOT fail the operation. The row is
  # already safe, and answering the visitor with an error would invite them to
  # submit again and create a duplicate.
  def send_notification(_ctx, website_lead:, **)
    WebsiteLeadMailer.with(website_lead_id: website_lead.id).new_lead.deliver_later
    true
  rescue StandardError => e
    Rails.logger.error "WebsiteLeadCreate: notification failed for lead #{website_lead.id} — #{e.class}: #{e.message}"
    true
  end

  private

  # Everything received, minus the two control fields, so the blob is a record of
  # what the form sent rather than what our anti-bot checks saw. Values are
  # stringified because a stray file upload would otherwise serialise as an
  # ActionDispatch::Http::UploadedFile.
  def raw_payload_json(params)
    payload = params.to_h.except("_hp", "_ts", :_hp, :_ts)
                    .transform_values { |value| value.is_a?(String) ? value : value.to_s }
    payload.to_json
  end

  # Collapses runs of whitespace and trims. Guards against the pasted-from-a-PDF
  # name that arrives with a non-breaking space on both ends.
  def squish(value)
    value.is_a?(String) ? value.squish.presence : value
  end

  def truncate(value, limit)
    value.is_a?(String) ? value.strip.first(limit).presence : value
  end
end
