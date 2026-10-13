Feature: NDA Status Dashboard (Module 3)
  As a GP I want to see which investors have accepted, declined, or are pending
  NDA acceptance for my Data Room folders, and manage stakeholder-level exemptions and signatory tagging.

  Background:
    Given there is a user "" for an entity "entity_type=Investment Fund;enable_funds=true"
    Given the entity has "enable_data_rooms" permission
    Given the GP entity has a data room folder
    Given the data room folder has an enabled NDA config

  # ── Phase 1: Data Layer — exempt_from_nda on InvestorAccess + NdaSignatory ──

  # Changed: Replaced NdaExemption model tests with InvestorAccess.exempt_from_nda tests.
  # Why: Per product decision (2026-10-05) — exemption is stakeholder-level, not user-level.

  # New InvestorAccess records default to exempt_from_nda = false.
  @rack_test
  Scenario: InvestorAccess defaults exempt_from_nda to false
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    Then the investor access exempt_from_nda should be false

  # GP can set exempt_from_nda to true on an InvestorAccess record.
  @rack_test
  Scenario: GP sets exempt_from_nda on InvestorAccess
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    When the GP sets exempt_from_nda to true for the investor access
    Then the investor access exempt_from_nda should be true

  # An NdaSignatory record can be created linking a user to an NDA config.
  @rack_test
  Scenario: NdaSignatory stores user and tagged_by
    Given there is an LP user for the GP entity
    When the GP tags the LP user as an NDA signatory
    Then an NDA signatory record should exist for the LP user
    And the NDA signatory tagged_by should be the GP user

  # Duplicate signatories are prevented by the unique constraint.
  @rack_test
  Scenario: Duplicate NdaSignatory is rejected
    Given there is an LP user for the GP entity
    When the GP tags the LP user as an NDA signatory
    Then creating a duplicate NDA signatory for the LP user should raise an error

  # Deleting an NDA config cascades to its signatories.
  @rack_test
  Scenario: NdaSignatory is destroyed when NdaConfig is destroyed
    Given there is an LP user for the GP entity
    When the GP tags the LP user as an NDA signatory
    And the NDA config is destroyed
    Then there should be 0 NDA signatories for the LP user

  # ── Phase 2: NdaStatusResolver ──────────────────────────────────────────────

  # The resolver returns the correct investor universe from InvestorAccess.
  @rack_test
  Scenario: Resolver returns investors from InvestorAccess
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    When the resolver resolves NDA status for the folder
    Then the resolver result should include investor "Acme Capital"
    And the resolver counters should show pending 1

  # The resolver correctly identifies an accepted investor.
  @rack_test
  Scenario: Resolver shows accepted status for investor that signed
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    And the investor "Acme Capital" has accepted the NDA
    When the resolver resolves NDA status for the folder
    Then the investor "Acme Capital" status should be "Accepted"
    And the resolver counters should show accepted 1

  # The resolver correctly identifies a declined investor.
  @rack_test
  Scenario: Resolver shows declined status for investor that declined
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    And the investor "Acme Capital" has declined the NDA
    When the resolver resolves NDA status for the folder
    Then the investor "Acme Capital" status should be "Declined"
    And the resolver counters should show declined 1

  # Changed: Investor status is Exempt when InvestorAccess has exempt_from_nda = true.
  # Why: Exemption is now stakeholder-level on InvestorAccess, not user-level NdaExemption.
  @rack_test
  Scenario: Investor status is Exempt when investor access is exempt
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    And the investor access has exempt_from_nda set to true
    When the resolver resolves NDA status for the folder
    Then the investor "Acme Capital" status should be "Exempt"
    And the resolver counters should show exempt 1

  # Investors without approved InvestorAccess do not appear in the resolver.
  Scenario: Unapproved investor does not appear in resolver results
    Given there is an LP investor "Acme Capital" with unapproved access to the GP entity
    When the resolver resolves NDA status for the folder
    Then the resolver result should not include investor "Acme Capital"

  # ── Phase 3: Gate — Stakeholder Exemption Check ─────────────────────────────

  # Changed: Gate checks InvestorAccess.exempt_from_nda instead of NdaExemption.
  # Why: Stakeholder-level exemption replaces user-level NdaExemption model.

  # An exempt stakeholder's user bypasses the NDA gate even if they have not accepted.
  @rack_test
  Scenario: Exempt stakeholder user bypasses NDA gate
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    And the investor access has exempt_from_nda set to true
    Then the NDA gate exemption check should pass for the LP user

  # A non-exempt stakeholder's user without acceptance is blocked by the gate.
  Scenario: Non-exempt stakeholder user with no acceptance is blocked
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    Then the NDA gate exemption check should not pass for the LP user

  # ── Phase 4: NdaStatusPolicy ────────────────────────────────────────────────

  # Changed: Removed create_exemption/destroy_exemption policy checks.
  # Why: Exemption is managed from InvestorAccess form, not from the NDA dashboard.

  # GP employees of the same entity are allowed to view the dashboard.
  @rack_test
  Scenario: GP employee is authorized for NDA status actions
    Then the NDA status policy should allow summary for the GP user
    And the NDA status policy should allow index for the GP user
    And the NDA status policy should allow create_signatory for the GP user
    And the NDA status policy should allow destroy_signatory for the GP user

  # LP users are denied access to the dashboard.
  @rack_test
  Scenario: LP user is denied NDA status actions
    Given there is an LP user for the GP entity
    Then the NDA status policy should deny summary for the LP user
    And the NDA status policy should deny index for the LP user

  # GP users from a different entity are denied access.
  @rack_test
  Scenario: Other-entity GP is denied NDA status actions
    Given there is a GP user from a different entity
    Then the NDA status policy should deny summary for the other GP user

  # ── Phase 5: Resolver Signatory Detection ──────────────────────────────────

  # Resolver shows nda_tagged true for a signatory user.
  @rack_test
  Scenario: Resolver shows signatory user as nda_tagged
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    And the LP user is tagged as a signatory for the NDA
    When the resolver resolves NDA status for the folder
    Then the LP user should be marked as nda_tagged in the resolver result

  # Resolver shows nda_tagged false for a non-signatory user. Auto-tag picks the
  # oldest approved user, so a second user under the same investor is not tagged.
  Scenario: Resolver shows non-signatory user as not nda_tagged
    Given there is an LP investor "Acme Capital" with approved access to the GP entity
    And there is a second LP user for "Acme Capital"
    When the resolver resolves NDA status for the folder
    Then the second LP user should not be marked as nda_tagged in the resolver result
