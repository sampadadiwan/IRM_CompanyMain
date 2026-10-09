Feature: NDA Acceptance (Module 2)
  As an LP I must accept an NDA before accessing an NDA-protected Data Room folder.
  As a GP I want to see an audit trail of LP accept/decline decisions.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the entity has "enable_data_rooms" permission
    Given the GP entity has a data room folder
    Given the data room folder has an enabled NDA config

  # ── Phase 1: Model and Audit Trail ────────────────────────────────────────

  # An NdaAcceptance record can be created with status "accepted" and
  # all audit fields are correctly populated.
  Scenario: NdaAcceptance record stores accepted status and audit fields (X4)
    Given there is an LP user for the GP entity
    When the LP accepts the NDA with audit metadata
    Then the NDA acceptance record should exist with status "accepted"
    And the NDA acceptance nda_version should match the NDA config version
    And the NDA acceptance ip_address should not be blank
    And the NDA acceptance user_agent should not be blank
    And the NDA acceptance accepted_at should not be nil
    And the NDA acceptance declined_at should be nil

  # An NdaAcceptance record can be created with status "declined" and
  # the declined_at timestamp is set instead of accepted_at.
  Scenario: NdaAcceptance record stores declined status and audit fields
    Given there is an LP user for the GP entity
    When the LP declines the NDA with audit metadata
    Then the NDA acceptance record should exist with status "declined"
    And the NDA acceptance declined_at should not be nil
    And the NDA acceptance accepted_at should be nil

  # Multiple acceptance records can exist for the same user and NDA config.
  # The latest record determines current access.
  Scenario: Multiple acceptance records are preserved (append-only)
    Given there is an LP user for the GP entity
    When the LP declines the NDA with audit metadata
    And the LP accepts the NDA with audit metadata
    Then there should be 2 NDA acceptance records for the LP
    And the latest NDA acceptance should have status "accepted"

  # The accepted? predicate returns true only for accepted records.
  Scenario: accepted? predicate returns correct values
    Given there is an LP user for the GP entity
    When the LP accepts the NDA with audit metadata
    Then the NDA acceptance accepted? should be true
    When the LP declines the NDA with audit metadata
    Then the latest NDA acceptance accepted? should be false

  # Validation rejects invalid status values.
  Scenario: NdaAcceptance rejects invalid status
    Given there is an LP user for the GP entity
    Then creating an NDA acceptance with status "pending" should fail validation

  # ── Phase 2: Policy ──────────────────────────────────────────────────────

  # GP employees (same entity as the NDA config) are denied by policy (R1).
  Scenario: Policy denies GP employee
    Given there is a GP user for the entity
    Then the NDA acceptance policy should deny the GP user

  # LP with approved investor access is allowed by policy (R2).
  Scenario: Policy allows LP with investor access
    Given there is an LP user for the GP entity
    And the LP has approved investor access to the GP entity
    Then the NDA acceptance policy should allow the LP user

  # User from unrelated entity (no investor access) is denied by policy (R5).
  Scenario: Policy denies user with no investor access
    Given there is an LP user without investor access for the GP entity
    Then the NDA acceptance policy should deny the LP user without investor access

  # ── Phase 4: NDA Gate on DocumentsController ─────────────────────────────

  # GP employee bypasses the NDA gate entirely (E5).
  Scenario: GP employee bypasses NDA gate
    Given there is a GP user for the entity
    Then the NDA gate should not block the GP user for the data room folder

  # Folder with no NDA config does not trigger the gate (E4).
  Scenario: Folder with no NDA config passes gate
    Given there is an LP user for the GP entity
    And there is a data room folder without NDA config
    Then the NDA gate should not block the LP for the folder without NDA

  # Disabled NDA config does not trigger the gate (E6).
  Scenario: Disabled NDA config passes gate
    Given there is an LP user for the GP entity
    And the NDA config is disabled
    Then the NDA gate should not block the LP for the data room folder

  # LP without acceptance is redirected by the gate (H1 precondition).
  Scenario: LP without acceptance is redirected by gate
    Given there is an LP user for the GP entity
    Then the NDA gate should redirect the LP to the acceptance screen

  # LP with accepted NDA passes through the gate (H2).
  Scenario: LP with accepted NDA passes gate
    Given there is an LP user for the GP entity
    When the LP accepts the NDA with audit metadata
    Then the NDA gate should not block the LP for the data room folder

  # Non-data-room folder is never gated.
  Scenario: Non-data-room folder bypasses gate
    Given there is an LP user for the GP entity
    And there is a non-data-room folder
    Then the NDA gate should not block the LP for the non-data-room folder

  # Opted-out folder (Module 5) is not gated even if parent has NDA (E3).
  Scenario: Opted-out folder bypasses gate
    Given there is an LP user for the GP entity
    And there is a child folder "Opted Out" in the data room
    And the folder "Opted Out" is opted out of NDA
    Then the NDA gate should not block the LP for the opted-out folder

  # safe_return_to rejects external URLs to prevent open redirect (X1).
  Scenario: safe_return_to rejects external URLs
    Then safe_return_to should reject "https://evil.com"
    And safe_return_to should reject "//evil.com"
    And safe_return_to should reject ""
    And safe_return_to should accept "/documents/folder?folder_id=123"
