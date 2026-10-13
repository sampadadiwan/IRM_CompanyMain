@rack_test
Feature: Grafana alert webhook forwards critical alerts to WhatsApp
  As the person on call for production
  I want Grafana's critical alerts to reach my phone
  So that an infrastructure problem wakes me even when I am not watching email

  # 2026-09-27: every Grafana WhatsApp alert failed. The WAF blocked real alert bodies
  # (403, EC2MetaDataSSRF_BODY), and anything that got through was refused 401: the
  # contact point sent its token as a custom X-Webhook-Token header, which Grafana 9.3
  # does not support, and the provisioned token had expanded to "". Grafana now sends
  # Authorization: Bearer <token>.

  Background:
    Given the Grafana webhook token is "grafana-test-token"
    And WhatsApp alert phones are configured
    And WATI accepts WhatsApp sends

  Scenario: An alert with the Bearer token Grafana 9.3 sends is forwarded
    When Grafana posts a firing alert with the header "Authorization" set to "Bearer grafana-test-token"
    Then the Grafana webhook should answer 200
    And a WhatsApp alert should have been sent to WATI

  Scenario: The legacy X-Webhook-Token header is still accepted
    When Grafana posts a firing alert with the header "X-Webhook-Token" set to "grafana-test-token"
    Then the Grafana webhook should answer 200

  Scenario: A wrong token is refused
    When Grafana posts a firing alert with the header "Authorization" set to "Bearer not-the-token"
    Then the Grafana webhook should answer 401
    And no WhatsApp alert should have been sent to WATI

  Scenario: The empty token the old provisioning produced is refused
    When Grafana posts a firing alert with the header "X-Webhook-Token" set to ""
    Then the Grafana webhook should answer 401

  Scenario: A send WATI rejects is reported to Grafana as a failure
    Given WATI rejects WhatsApp sends
    When Grafana posts a firing alert with the header "Authorization" set to "Bearer grafana-test-token"
    Then the Grafana webhook should answer 502

  # WhatsappGeneralNotification.parse_response returns WATI's JSON body whatever the HTTP
  # status, so an auth or rate-limit error must not read as a delivered alert.
  Scenario: A WATI error that is not an explicit acceptance is reported to Grafana as a failure
    Given WATI answers '{"message":"Unauthorized"}'
    When Grafana posts a firing alert with the header "Authorization" set to "Bearer grafana-test-token"
    Then the Grafana webhook should answer 502
