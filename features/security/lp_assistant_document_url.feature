Feature: LP assistant document links follow the documents screen - 2026-10 security review (H4)
  The LP assistant's document_url tool handed out a signed link for any document owned by a fund,
  call, distribution or commitment the LP could reach, including unapproved generated drafts,
  private-folder documents and templates. It now also asks DocumentPolicy#show? for the LP - the
  rule of the LP documents screen - and never resolves a template.
  Design and worked examples: docs/security/security_review_2026_10.md#h4--lp-assistant-document_url

  Background:
    Given there is a user "first_name=Gita" for an entity "entity_type=Investment Fund;name=Artha FM"
    And there is a fund "name=Artha Growth Fund" for the entity
    And an LP scope is set up with entity "Artha FM" and fund "Artha Growth Fund"
    And the LP has a commitment in the LP's fund

  # H4-1 — Edge case: the LP's own SOA, generated but not yet approved, is a draft the fund has not released
  @security
  Scenario: H4-1 An unapproved generated SOA has no link
    Given the LP's own SOA "SOA - Q1 2026" is generated but not approved
    When the LP requests the URL for that document
    Then the document response should include "not found or not accessible"

  # H4-2 — Edge case: a fund template is a blueprint, never an LP document
  @security
  Scenario: H4-2 A fund template has no link
    Given a template "SOA Template v2" in the LP's fund
    When the LP requests the URL for that document
    Then the document response should include "not found or not accessible"

  # H4-3 — Edge case: a document in a private folder of the LP's fund stays with the fund team
  @security
  Scenario: H4-3 A private-folder document has no link
    Given a fund document "Board Pack" in a private folder of the LP's fund
    When the LP requests the URL for that document
    Then the document response should include "not found or not accessible"

  # H4-4 — Edge case: a generated call notice not yet approved is unreleased
  @security
  Scenario: H4-4 An unreleased call notice has no link
    Given an unreleased notice "Call 1 Notice" generated for a capital call of the LP's fund
    When the LP requests the URL for that document
    Then the document response should include "not found or not accessible"

  # H4-H — Happy path: the LP's approved SOA opens, as on the documents screen
  @security
  Scenario: H4-H An approved SOA gets a link
    Given the LP's own SOA "SOA - Q4 2025" is generated and approved
    When the LP requests the URL for that document
    Then the document response should be a download URL

  # H4-H — Happy path: a data room document of a fund the LP has an access right on opens
  @security
  Scenario: H4-H A data room document gets a link
    Given a data room document "LPA v2" of the LP's fund
    When the LP requests the URL for that document
    Then the document response should be a download URL

  # H4-X — Error case: another LP's SOA in the same fund is refused, as before
  @security
  Scenario: H4-X Another LP's SOA has no link
    Given another investor has an SOA "SOA - Q4 2025" attached to their commitment in the LP's fund
    When the LP requests the URL for that document
    Then the document response should include "not found or not accessible"
