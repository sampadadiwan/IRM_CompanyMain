# frozen_string_literal: true

Feature: NDA Enhancements (Module 9)
  As a GP I want default signatories auto-tagged on NDA creation, non-signatory
  LPs blocked from the acceptance screen, and a version history audit trail.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the entity has "enable_data_rooms" permission
    Given the GP entity has a data room folder

  # ── Auto-tagging Default Signatories ────────────────────────────────────────

  # When NDA config is created, the oldest approved user per investor is
  # auto-tagged as a signatory.
  Scenario: Auto-tag creates signatory for each investor on NDA creation
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    And there is a second LP investor "Beta Fund" with approved access to the GP entity
    When the GP creates an NDA config with auto-tagging
    Then there should be 1 NDA signatory for investor "Acme Capital"
    And there should be 1 NDA signatory for investor "Beta Fund"

  # The auto-tagged signatory is the oldest approved user (by InvestorAccess.created_at).
  Scenario: Auto-tag picks the oldest approved user
    Given there is an LP investor "Acme Capital" with two approved users
    When the GP creates an NDA config with auto-tagging
    Then the auto-tagged signatory for "Acme Capital" should be the oldest user

  # Auto-tagging is idempotent — duplicate signatories are silently skipped.
  Scenario: Auto-tag silently skips if signatory already exists
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    And the data room folder has an enabled NDA config
    And the LP user is already a signatory for the NDA
    When auto-tagging is run for the NDA config
    Then there should be 1 NDA signatory for investor "Acme Capital"

  # ── Non-signatory Blocked Page ──────────────────────────────────────────────

  # A non-signatory LP user is identified as blocked by the signatory check.
  Scenario: Non-signatory user is identified as blocked
    Given the data room folder has an enabled NDA config
    And there is an LP investor "Acme Capital" with approved access to the GP entity
    Then the LP user should be identified as a non-signatory for the NDA

  # A signatory LP user passes the signatory check.
  Scenario: Signatory user passes the signatory check
    Given the data room folder has an enabled NDA config
    And there is an LP investor "Acme Capital" with approved access to the GP entity
    And the LP user is tagged as a signatory for the NDA
    Then the LP user should be identified as a signatory for the NDA

  # ── Gate: Signatory vs Non-signatory Redirect ──────────────────────────────

  # Non-signatory with no acceptance → gate would redirect to blocked page.
  Scenario: Gate directs non-signatory to blocked page (no acceptance)
    Given the data room folder has an enabled NDA config
    And there is an LP investor "Acme Capital" with approved access to the GP entity
    Then the gate target for the LP user should be "blocked"

  # Signatory with no acceptance → gate would redirect to acceptance screen.
  Scenario: Gate directs signatory to acceptance screen (no acceptance)
    Given the data room folder has an enabled NDA config
    And there is an LP investor "Acme Capital" with approved access to the GP entity
    And the LP user is tagged as a signatory for the NDA
    Then the gate target for the LP user should be "acceptance"

  # Non-signatory with stale version acceptance → gate would redirect to blocked page.
  Scenario: Gate directs non-signatory to blocked page (stale version)
    Given the data room folder has an enabled NDA config
    And there is an LP investor "Acme Capital" with approved access to the GP entity
    And the investor "Acme Capital" has accepted the NDA at version 1
    And the NDA config version is bumped to 2
    Then the gate target for the LP user should be "blocked"

  # Signatory with stale version acceptance → gate would redirect to acceptance screen.
  Scenario: Gate directs signatory to acceptance screen (stale version)
    Given the data room folder has an enabled NDA config
    And there is an LP investor "Acme Capital" with approved access to the GP entity
    And the LP user is tagged as a signatory for the NDA
    And the investor "Acme Capital" has accepted the NDA at version 1
    And the NDA config version is bumped to 2
    Then the gate target for the LP user should be "acceptance"

  # ── NdaConfigVersion Audit Trail ────────────────────────────────────────────

  # Version record stores the correct Shrine document data.
  Scenario: Version record stores nda_document_data
    Given the data room folder has an enabled NDA config
    When a version 1 record is created for the NDA config
    Then the version record nda_document_data should match the NDA config

  # Version uniqueness constraint — cannot create two records with same version.
  Scenario: Duplicate version number is rejected
    Given the data room folder has an enabled NDA config
    When a version 1 record is created for the NDA config
    Then creating a duplicate version 1 record should raise an error

  # ── VALID_REASONS Whitelist ─────────────────────────────────────────────────

  # Only whitelisted reasons are accepted by the acceptance controller.
  Scenario: VALID_REASONS includes version_mismatch, expired, and revoked
    Then the NDA acceptance VALID_REASONS should include "version_mismatch"
    And the NDA acceptance VALID_REASONS should include "expired"
    And the NDA acceptance VALID_REASONS should include "revoked"
    And the NDA acceptance VALID_REASONS should not include "hacked"
