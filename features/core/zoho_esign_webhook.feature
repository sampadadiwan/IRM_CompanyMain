@doc_gen
Feature: Zoho eSign webhook signature verification

  Inbound Zoho Sign webhook requests (documents/signature_progress) are HMAC-signature
  verified via the X-ZS-WEBHOOK-SIGNATURE header (ZohoEsignHelper.verify_signature). This
  endpoint skips normal authentication, so an invalid signature must be rejected outright.

Scenario: A Zoho eSign webhook request with an invalid signature is rejected
  Given the Zoho eSign webhook signature verification will fail
  When a Zoho eSign webhook request is received with an invalid signature
  Then the webhook request is rejected as unauthorized
