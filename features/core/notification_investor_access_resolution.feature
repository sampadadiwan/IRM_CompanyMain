@rack_test
Feature: Notification channel gates read the access of the folio the notification is about
  Covers NotificationExtensions#investor_access / #email_enabled / #whatsapp_enabled
  (config/initializers/noticed.rb) for a contact who holds two investor accesses in the same
  fund. Access "a" (Folio A) is always created before access "b" (Folio B), so "a" has the
  lower id - the row the old `.first` lookup always picked.
  As in investor_kyc_notification_delivery.feature, the notification is built directly and the
  gate called on it, because BaseNotifier's test-env :email deliver_by skips email_enabled.
  Report: openspec/changes/fix-notification-investor-access-resolution/report.md#verification

  Background:
    Given there is a user "first_name=FundAdmin" for an entity "name=FolioGateFund;entity_type=Investment Fund"
    And the user has role "company_admin"
    And there is a fund "name=FolioGateFund1" for the entity "name=FolioGateFund"
    And the contact "two.folio@example.com" holds access "a" on folio "Folio A" and access "b" on folio "Folio B"

  # H1 — Happy path: a document for the contact's own folio B uses B's switch, not A's (asrikanth case)
  @folio_gate
  Scenario: Document for folio B is emailed when B has email on and the older access A has it off
    Given access "a" has email "off"
    And access "b" has email "on"
    And there is a document owned by the commitment of folio "Folio B"
    When I build a document notification for the contact naming folio "Folio B"
    Then email_enabled should be true for the notification

  # H2 — Happy path: a record that names its own investor (a commitment) is unchanged
  @folio_gate
  Scenario: Commitment notification for folio A still follows A's switch
    Given access "a" has email "off"
    And access "b" has email "on"
    When I build a commitment notification for the contact on folio "Folio A"
    Then email_enabled should be false for the notification

  # H3 — Happy path: folio B's opt-out is respected even though the older access A has email on (dhairavs case)
  @folio_gate
  Scenario: Document for folio B is not emailed when B has email off
    Given access "a" has email "on"
    And access "b" has email "off"
    And there is a document owned by the commitment of folio "Folio B"
    When I build a document notification for the contact naming folio "Folio B"
    Then email_enabled should be false for the notification

  # E1 — Edge case: no investor_id in the params (events before 2026-10-07, other senders); folio comes from the document's owner
  @folio_gate
  Scenario: Folio is taken from the document's owning commitment when the params do not name it
    Given access "a" has email "off"
    And access "b" has email "on"
    And there is a document owned by the commitment of folio "Folio B"
    When I build a document notification for the contact without a folio
    Then email_enabled should be true for the notification

  # E2 — Edge case: no folio can be found at all (a fund-level document) - email if ANY of the contact's accesses in the fund has it on
  @folio_gate
  Scenario: Fund-level document with no folio uses "any access enabled"
    Given access "a" has email "off"
    And access "b" has email "on"
    And there is a document owned by the fund
    When I build a document notification for the contact without a folio
    Then email_enabled should be true for the notification
    Given access "b" has email "off"
    When I build a document notification for the contact without a folio
    Then email_enabled should be false for the notification

  # E3 — Edge case: WhatsApp follows the same folio as email, independently of the older access
  @folio_gate
  Scenario: WhatsApp for a folio-B document uses B's WhatsApp switch
    Given the fund entity has WhatsApp enabled and the contact can receive WhatsApp
    And access "a" has email "off"
    And access "a" has whatsapp "on"
    And access "b" has email "on"
    And access "b" has whatsapp "off"
    And there is a document owned by the commitment of folio "Folio B"
    When I build a document notification for the contact naming folio "Folio B"
    Then email_enabled should be true for the notification
    And whatsapp_enabled should be false for the notification
    And the WhatsApp delivery check should be false for the notification

  # E4 — Edge case: document owned directly by the Investor record of folio B
  @folio_gate
  Scenario: Document owned by the investor itself resolves that investor's folio
    Given access "a" has email "off"
    And access "b" has email "on"
    And there is a document owned by the investor of folio "Folio B"
    When I build a document notification for the contact without a folio
    Then email_enabled should be true for the notification

  # E5 — Edge case: a contact with a single access is unaffected by the change
  @folio_gate
  Scenario: Single-access contact still gets the email
    Given the contact "solo.folio@example.com" holds access "s" on folio "Folio B"
    And access "s" has email "on"
    And there is a document owned by the commitment of folio "Folio B"
    When I build a document notification for "solo.folio@example.com" without a folio
    Then email_enabled should be true for the notification

  # X1 — Error case: params name a folio the contact has no access on - no fallback to another folio
  @folio_gate
  Scenario: Folio without an access for the contact is not emailed
    Given access "a" has email "on"
    And access "b" has email "on"
    And there is a folio "Folio C" in the fund without the contact
    And there is a document owned by the commitment of folio "Folio C"
    When I build a document notification for the contact naming folio "Folio C"
    Then email_enabled should be false for the notification

  # X2 — Error case: params name an investor that no longer exists - fall back to the document's owner, no exception
  @folio_gate
  Scenario: Missing investor in the params falls back to the document's owner
    Given access "a" has email "off"
    And access "b" has email "on"
    And there is a document owned by the commitment of folio "Folio B"
    When I build a document notification for the contact naming a missing investor
    Then email_enabled should be true for the notification

  # X3 — Error case: an LP email gated off leaves a log line naming the notification, folio and access
  @folio_gate
  Scenario: Email gated off is logged with the resolved folio and access
    Given access "a" has email "on"
    And access "b" has email "off"
    And there is a document owned by the commitment of folio "Folio B"
    When I build a document notification for the contact naming folio "Folio B"
    Then email_enabled should be false for the notification
    And the email gate log should name folio "Folio B" and access "b"
