# frozen_string_literal: true

# Receives Grafana alert webhooks and forwards them to WhatsApp via WATI.
#
# Setup:
#   1. Add GRAFANA_WEBHOOK_TOKEN to Rails credentials:
#      bundle exec rails credentials:edit
#      grafana_webhook_token: "your-secret-token-here"
#
#   2. Add GRAFANA_ALERT_PHONES to Rails credentials, E.164 without the '+'. Preferred
#      shape is a list, which has no separator to lose:
#        grafana_alert_phones:
#          - "917721046692"
#          - "919876543210"
#      A quoted CSV string also works. QUOTE IT either way — unquoted, YAML reads a run of
#      digits as an Integer, and a dropped comma fuses both numbers into one bignum that
#      WATI rejects with "There are no valid Receivers":
#        grafana_alert_phones: "917721046692,919876543210"
#
#   3. Provision the contact point: `rake grafana:provision:contact_points` points each
#      region's Grafana at its OWN app with that app's token (Authorization: Bearer) —
#      graphana.caphive.com -> app.caphive.com, graphana.caphive.us -> app.caphive.us.
#      IN and US are independent environments; neither alerts through the other.
#
# Why Bearer: Grafana 9.3's webhook contact point has no custom-header setting (its
# options are url, httpMethod, basic auth, authorization_scheme/_credentials, maxAlerts,
# title, message). The X-Webhook-Token header this endpoint used to require was
# provisioned as `httpHeaders`, which Grafana silently ignored — and the token in it had
# expanded to "" anyway — so every alert that got past the WAF was answered 401.
# X-Webhook-Token is still accepted for anything calling this by hand.
class GrafanaAlertsController < ActionController::API
  before_action :verify_token

  # POST /grafana/alert
  def alert
    payload = JSON.parse(request.body.read)
    message = format_alert(payload)
    phones  = OpsWhatsappAlert.configured_phones

    if phones.empty?
      # "Deliberately unconfigured" and "configured but unusable" must not answer alike.
      # The second is how this endpoint failed for months — a broken credential that still
      # returned 200 left Grafana's contact point green while every alert was dropped. So
      # it fails loudly and lets Grafana mark the contact point down.
      if Rails.application.credentials[:grafana_alert_phones].present?
        Rails.logger.error '[GrafanaAlert] credentials[:grafana_alert_phones] is set but ' \
                           'contains no digits — check the separators and that it is quoted'
        render json: { error: 'no_valid_alert_phones' }, status: :bad_gateway and return
      end

      Rails.logger.warn '[GrafanaAlert] No phones configured in credentials[:grafana_alert_phones]'
      render json: { status: 'ok', note: 'no phones configured' } and return
    end

    result = OpsWhatsappAlert.deliver(
      message,
      title: 'CapHive Infrastructure',
      # Link to the Grafana instance that fired, taken from the alert's region label
      link: grafana_link_path(payload),
      broadcast_name: 'Grafana Alerts',
      phones: phones
    )
    response = result.response

    # Always log the raw WATI body. This return value used to be discarded, so a rejected
    # send logged "Sent to 2 number(s)" and answered Grafana with 200 — the contact point
    # showed green while nothing was ever delivered.
    unless result.ok?
      # Recipients are logged alongside the response because WATI's commonest rejection
      # ("There are no valid Receivers") names no number — without them the log says the
      # send failed but not which address it choked on.
      Rails.logger.error "[GrafanaAlert] WATI rejected the send to #{OpsWhatsappAlert.mask_phones(phones)}: " \
                         "#{response.inspect.truncate(500)}"
      # 502 so Grafana marks the contact point as failing and retries, instead of
      # recording a successful notification.
      render json: { error: 'whatsapp_delivery_failed', wati: response }, status: :bad_gateway and return
    end

    Rails.logger.info "[GrafanaAlert] Sent to #{phones.size} number(s): #{message.truncate(120)} " \
                      "| WATI: #{response.inspect.truncate(300)}"
    render json: { status: 'ok' }
  rescue JSON::ParserError => e
    Rails.logger.error "[GrafanaAlert] Bad JSON: #{e.message}"
    render json: { error: 'invalid_json' }, status: :bad_request
  rescue => e
    Rails.logger.error "[GrafanaAlert] #{e.class}: #{e.message}"
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def verify_token
    expected = Rails.application.credentials[:grafana_webhook_token].to_s
    received = bearer_token || request.headers['X-Webhook-Token'].to_s
    return head :unauthorized unless expected.present? && ActiveSupport::SecurityUtils.secure_compare(received, expected)
  end

  def bearer_token
    request.authorization.to_s[/\ABearer (.+)\z/, 1]
  end

  # region=in/us label is injected on every rule by rake grafana:provision:alert_rules —
  # one webhook payload always comes from a single Grafana instance, so the first
  # alert's region identifies the whole batch. Empty string for pre-region alerts.
  def payload_region(payload)
    Array(payload['alerts']).filter_map { |a| a.dig('labels', 'region') }.first.to_s
  end

  # WhatsApp "link" param. The template's button is a Meta URL button, so this value is
  # appended to a base fixed at approval time (the app's own URL) — it must be a
  # path, never a hostname. Passing 'graphana.caphive.com' here is what produced the
  # button pointing at https://app.caphive.com/graphana.caphive.com. The path resolves
  # through the GET /grafana/:region redirect in routes.rb, which knows the hostnames.
  def grafana_link_path(payload)
    "grafana/#{payload_region(payload) == 'us' ? 'us' : 'in'}"
  end

  def format_alert(payload)
    alerts   = Array(payload['alerts'])
    firing   = alerts.select { |a| a['status'] == 'firing' }
    resolved = alerts.select { |a| a['status'] == 'resolved' }

    # "[IN] " / "[US] " tag so the message says which region's servers are affected
    region = payload_region(payload)
    tag    = region.empty? ? '' : "[#{region.upcase}] "

    header = if firing.any? && resolved.any?
      "#{tag}ALERT: #{firing.size} firing, #{resolved.size} resolved"
    elsif firing.any?
      "#{tag}ALERT: #{firing.size} issue#{firing.size > 1 ? 's' : ''} firing"
    else
      "#{tag}RESOLVED: #{resolved.size} issue#{resolved.size > 1 ? 's' : ''}"
    end

    segments = [header]
    alerts.first(5).each do |a|
      icon    = a['status'] == 'firing' ? '[!]' : '[OK]'
      title   = a.dig('labels', 'alertname') || 'Unknown alert'
      summary = a.dig('annotations', 'summary') || ''
      # The provisioner bakes "[IN] "/"[US] " into every summary (needed for email body
      # text) — strip it here since the header already carries the tag, so WhatsApp
      # messages don't repeat it per line and waste the 1000-char truncate budget
      summary = summary.delete_prefix(tag)
      # Summary joined to its own title with ": " so one alert stays one segment —
      # the " · " separator then reads as the boundary between distinct alerts.
      segments << (summary.empty? ? "#{icon} #{title}" : "#{icon} #{title}: #{summary}")
    end
    segments << "... and #{alerts.size - 5} more" if alerts.size > 5

    # Single line, joined with " · ". WhatsApp rejects template PARAMETER values that
    # contain newlines, tabs, or runs of 4+ spaces — the template body may have line
    # breaks, but the variables spliced into it may not. This message is one such
    # variable, so it can never contain them. OpsWhatsappAlert.sanitize also scrubs whitespace
    # inside each segment, since Grafana summary annotations are free text.
    segments.map { |s| OpsWhatsappAlert.sanitize(s) }.reject(&:empty?).join(' · ')
  end
end
