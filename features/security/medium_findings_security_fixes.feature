Feature: Medium security fixes (M2, M3, M5)
  As a security-conscious system
  I want document-share tokens to expire, the doc-share index to be tenant-scoped,
  and investor-access grants to be limited to company admins
  So that leaked links, cross-tenant metadata, and unauthorized grants are prevented

  # ──────────────────────────────────────────────────────────────────────────
  # M2: document share tokens must expire
  # ──────────────────────────────────────────────────────────────────────────

  @rack_test
  Scenario: A fresh document share token resolves
    Given a document share for a security test exists
    When a share token is generated with the default expiry
    Then the share token resolves to the doc share id

  Scenario: An expired document share token is rejected
    Given a document share for a security test exists
    When a share token is generated that has already expired
    Then the share token does not resolve

  # ──────────────────────────────────────────────────────────────────────────
  # M3: a company admin only sees doc shares from their own entity
  # ──────────────────────────────────────────────────────────────────────────

  @rack_test
  Scenario: The doc-share index scope is bounded to the admin's entity
    Given a company admin in a security test entity with a shared document
    And a different security test entity with its own shared document
    Then the company admin's doc share scope includes only their own entity's share

  # ──────────────────────────────────────────────────────────────────────────
  # M5: only company admins may grant investor access
  # ──────────────────────────────────────────────────────────────────────────

  @rack_test
  Scenario: A company admin may grant and approve investor access
    Given an investor access record in a managing entity
    And a company admin of that managing entity
    Then the company admin may create and approve the investor access

  Scenario: A regular employee may not grant or approve investor access
    Given an investor access record in a managing entity
    And a regular employee of that managing entity
    Then the employee may not create or approve the investor access

  # ──────────────────────────────────────────────────────────────────────────
  # M10: document-template filters cannot inject SQL via the field name
  # ──────────────────────────────────────────────────────────────────────────

  @rack_test
  Scenario: A template filter on a real column is applied
    Given a decorated entity collection for a security test
    Then filtering by the column "name" is allowed

  Scenario: A template filter with an injected field name is neutralized
    Given a decorated entity collection for a security test
    Then filtering by an injected field returns no rows and raises no SQL error
