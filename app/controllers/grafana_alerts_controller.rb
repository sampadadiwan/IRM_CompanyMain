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
              { name: 'link',         value: 'graphana.caphive.com' }
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

  def format_alert(payload)
    alerts   = Array(payload['alerts'])
    firing   = alerts.select { |a| a['status'] == 'firing' }
    resolved = alerts.select { |a| a['status'] == 'resolved' }

    header = if firing.any? && resolved.any?
      "ALERT: #{firing.size} firing, #{resolved.size} resolved"
    elsif firing.any?
      "ALERT: #{firing.size} issue#{firing.size > 1 ? 's' : ''} firing"
    else
      "RESOLVED: #{resolved.size} issue#{resolved.size > 1 ? 's' : ''}"
    end

    lines = [header, '']
    alerts.first(5).each do |a|
      icon    = a['status'] == 'firing' ? '[!]' : '[OK]'
      title   = a.dig('labels', 'alertname') || 'Unknown alert'
      summary = a.dig('annotations', 'summary') || ''
      lines << "#{icon} #{title}"
      lines << "    #{summary}" unless summary.empty?
    end
    lines << "... and #{alerts.size - 5} more" if alerts.size > 5

    lines.join("\n")
  end
end
