# frozen_string_literal: true

# Receives Grafana alert webhooks and forwards them to WhatsApp via WATI.
#
# Setup:
#   1. Add GRAFANA_WEBHOOK_TOKEN to Rails credentials:
#      bundle exec rails credentials:edit
#      grafana_webhook_token: "your-secret-token-here"
#
#   2. Add GRAFANA_ALERT_PHONES to Rails credentials (comma-separated, E.164 without +):
#      grafana_alert_phones: "917721046692,919876543210"
#
#   3. In Grafana → Contact Points → Caphive WhatsApp → set:
#      URL: https://app.caphive.com/grafana/alert
#      HTTP Headers: X-Webhook-Token: <token from step 1>
class GrafanaAlertsController < ActionController::API
  before_action :verify_token

  # POST /grafana/alert
  def alert
    payload = JSON.parse(request.body.read)
    message = format_alert(payload)
    phones  = Rails.application.credentials[:grafana_alert_phones].to_s
                   .split(',').map(&:strip).reject(&:empty?)

    if phones.empty?
      Rails.logger.warn '[GrafanaAlert] No phones configured in credentials[:grafana_alert_phones]'
      render json: { status: 'ok', note: 'no phones configured' } and return
    end

    template = ENV.fetch('CAPHIVE_NOTIFICATION', 'caphive_notification_6')

    response = WhatsappGeneralNotification.send_template_message(
      {
        recipients: phones.map do |phone|
          {
            phone_number: phone,
            custom_params: [
              { name: '1',            value: 'CapHive Infrastructure' },
              { name: 'notification', value: message.truncate(1000) },
              # Link to the Grafana instance that actually fired (IN vs US) — both
              # instances post to this same endpoint, so derive it from the payload
              { name: 'link',         value: grafana_host(payload) }
            ]
          }
        end
      },
      template_name:  template,
      broadcast_name: 'Grafana Alerts'
    )

    # Always log the raw WATI body. This return value used to be discarded, so a rejected
    # send logged "Sent to 2 number(s)" and answered Grafana with 200 — the contact point
    # showed green while nothing was ever delivered.
    if delivery_failed?(response)
      Rails.logger.error "[GrafanaAlert] WATI rejected the send: #{response.inspect.truncate(500)}"
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

  # WATI reports a rejected template send inside a 200 body rather than via HTTP status,
  # and the exact shape varies by plan/endpoint version. Treat the send as failed only on
  # a positive failure signal — an unrecognised body is logged verbatim by the caller, so
  # an undocumented shape stays diagnosable without falsely failing every alert.
  FAILURE_RESULTS = %w[false failure failed error].freeze

  private

  def delivery_failed?(response)
    # Non-Hash means the transport helper returned something unexpected; the caller logs it.
    return false unless response.is_a?(Hash)

    # WhatsappGeneralNotification.parse_response returns {"error" => "non_json_response"}
    # when WATI answers with HTML (auth failure, gateway error) — caught here too.
    return true if response['error'].present?
    return true if response['errors'].is_a?(Hash) && response.dig('errors', 'error').present?
    return true if response['result'] == false

    result = response['result']
    result.is_a?(String) && FAILURE_RESULTS.include?(result.downcase)
  end

  def verify_token
    expected = Rails.application.credentials[:grafana_webhook_token]
    received = request.headers['X-Webhook-Token']
    return head :unauthorized unless expected.present? && received == expected
  end

  # region=in/us label is injected on every rule by rake grafana:provision:alert_rules —
  # one webhook payload always comes from a single Grafana instance, so the first
  # alert's region identifies the whole batch. Empty string for pre-region alerts.
  def payload_region(payload)
    Array(payload['alerts']).filter_map { |a| a.dig('labels', 'region') }.first.to_s
  end

  # WhatsApp "link" param: point at the Grafana instance that fired, not always IN
  def grafana_host(payload)
    payload_region(payload) == 'us' ? 'graphana.caphive.us' : 'graphana.caphive.com'
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
    # variable, so it can never contain them. sanitize_param also scrubs whitespace
    # inside each segment, since Grafana summary annotations are free text.
    segments.map { |s| sanitize_param(s) }.reject(&:empty?).join(' · ')
  end

  # Collapse every whitespace run (newline, tab, multi-space) to a single space so the
  # value is always legal as a WhatsApp template variable.
  def sanitize_param(text)
    text.to_s.gsub(/\s+/, ' ').strip
  end
end
