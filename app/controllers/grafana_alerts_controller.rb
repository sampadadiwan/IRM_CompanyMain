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

    WhatsappGeneralNotification.send_template_message(
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

    Rails.logger.info "[GrafanaAlert] Sent to #{phones.size} number(s): #{message.truncate(120)}"
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

    lines = [header, '']
    alerts.first(5).each do |a|
      icon    = a['status'] == 'firing' ? '[!]' : '[OK]'
      title   = a.dig('labels', 'alertname') || 'Unknown alert'
      summary = a.dig('annotations', 'summary') || ''
      # The provisioner bakes "[IN] "/"[US] " into every summary (needed for email body
      # text) — strip it here since the header already carries the tag, so WhatsApp
      # messages don't repeat it per line and waste the 1000-char truncate budget
      summary = summary.delete_prefix(tag)
      lines << "#{icon} #{title}"
      lines << "    #{summary}" unless summary.empty?
    end
    lines << "... and #{alerts.size - 5} more" if alerts.size > 5

    lines.join("\n")
  end
end
