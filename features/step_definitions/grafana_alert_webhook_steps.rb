# Steps for features/core/grafana_alert_webhook.feature.
#
# The endpoint is called in-process through Rack::MockRequest — it is an API with no page
# to drive — and WATI is stubbed, so nothing leaves the test.

GRAFANA_FIRING_ALERT = {
  alerts: [{
    status: 'firing',
    labels: { alertname: 'Disk Critical (>90%)', severity: 'critical', region: 'in' },
    annotations: { summary: '[IN] Disk usage has exceeded 90% on at least one filesystem' }
  }]
}.freeze

Given('the Grafana webhook token is {string}') do |token|
  allow(Rails.application.credentials).to receive(:[]).and_call_original
  allow(Rails.application.credentials).to receive(:[]).with(:grafana_webhook_token).and_return(token)
end

Given('WhatsApp alert phones are configured') do
  allow(Rails.application.credentials).to receive(:[]).with(:grafana_alert_phones).and_return(['917721046692'])
end

Given('WATI accepts WhatsApp sends') do
  @wati_sends = []
  allow(WhatsappGeneralNotification).to receive(:send_template_message) do |params, **_opts|
    @wati_sends << params
    { 'success' => true, 'recipients' => [{ 'phone_number' => '917721046692', 'errors' => [] }] }
  end
end

Given('WATI rejects WhatsApp sends') do
  allow(WhatsappGeneralNotification).to receive(:send_template_message)
    .and_return({ 'success' => false, 'error' => 'There are no valid Receivers', 'recipients' => [] })
end

Given('WATI answers {string}') do |json|
  allow(WhatsappGeneralNotification).to receive(:send_template_message).and_return(JSON.parse(json))
end

When('Grafana posts a firing alert with the header {string} set to {string}') do |header, value|
  rack_header = header == 'Authorization' ? 'HTTP_AUTHORIZATION' : "HTTP_#{header.upcase.tr('-', '_')}"
  env = Rack::MockRequest.env_for('/grafana/alert', method: 'POST', input: GRAFANA_FIRING_ALERT.to_json,
                                                    'CONTENT_TYPE' => 'application/json', rack_header => value)
  @grafana_status, = Rails.application.call(env)
end

Then('the Grafana webhook should answer {int}') do |status|
  expect(@grafana_status).to eq(status)
end

Then('a WhatsApp alert should have been sent to WATI') do
  expect(@wati_sends.size).to eq(1)
end

Then('no WhatsApp alert should have been sent to WATI') do
  expect(@wati_sends).to be_empty
end
